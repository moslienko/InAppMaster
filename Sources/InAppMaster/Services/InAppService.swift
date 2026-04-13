//
//  InAppService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 12.04.2026.
//

import StoreKit

final public class InAppService {
    
    // MARK: - Params
    static public let shared = InAppService()
    private var configuredProductIdentifiers: [String] = []
    
    /// iOS 13-14
    public lazy var legacyService = InAppLegacyService.shared
    
    /// iOS 15+
    @available(iOS 15.0, *)
    @MainActor
    public var modernService: InAppModernService {
        InAppModernService.shared
    }
    
    // MARK: - Init
    private init() {}
    
    // MARK: - Methods
    
    /// Configures the in-app purchase service with the given product identifiers.
    /// - Parameter productIdentifiers: The list of product identifiers to be loaded.
    public func configure(productIdentifiers: [String]) {
        configuredProductIdentifiers = productIdentifiers

        if #unavailable(iOS 15.0) {
            legacyService.configure(productIdentifiers: productIdentifiers)
        }
    }
    
    /// Fetch the available in-app products from the App Store.
    /// - Parameter completion: A closure called with the result containing the fetched products on success, or an error on failure.
    public func fetchProducts(
        completion: @escaping (Result<[any InAppProductProtocol], Error>) -> Void
    ) {
        if #available(iOS 15.0, *) {
            Task {
                do {
                    let products = try await modernService.fetchAvailableProducts(
                        productIdentifiers: self.configuredProductIdentifiers
                    )
                    await MainActor.run {
                        completion(.success(products))
                    }
                } catch {
                    await MainActor.run {
                        completion(.failure(error))
                    }
                }
            }
        } else {
            legacyService.productsInfoRequestDidFinished = { products in
                completion(.success(products))
            }
            legacyService.productsFetchDidFailed = { error in
                completion(.failure(error))
            }
            legacyService.fetchAvailableProducts()
        }
    }
    
    /// Initiates a purchase for the product with the given identifier.
    /// - Parameters:
    ///   - id: The identifier of the product.
    ///   - completion: A closure called with the result containing the purchased on success, or an error on failure.
    public func purchaseProduct(id: String, completion: @escaping (Result<String, Error>) -> Void) {
        if #available(iOS 15.0, *) {
            Task {
                do {
                    try await modernService.purchaseMyProduct(id: id)
                    completion(.success(id))
                } catch {
                    completion(.failure(error))
                }
            }
        } else {
            legacyService.productDidSuccessPurchased = { id in
                completion(.success(id))
            }
            legacyService.productDidFailedPurchased = { error in
                completion(.failure(error))
            }
            legacyService.purchaseMyProduct(id: id)
        }
    }
    
    /// Restores previously purchased.
    /// - Parameter completion: A closure called with the result containing the identifiers of the restored products on success, or an error on failure.
    public func restoreProducts(completion: @escaping (Result<[String], Error>) -> Void) {
        if #available(iOS 15.0, *) {
            Task {
                do {
                    let purchasedProducts = try await modernService.restorePurchase()
                    completion(.success(Array(purchasedProducts)))
                } catch {
                    completion(.failure(error))
                }
            }
        } else {
            legacyService.productDidSuccessRestored = { ids in
                completion(.success(ids))
            }
            legacyService.productDidFailedRestored = { error in
                completion(.failure(error))
            }
            legacyService.restorePurchase()
        }
    }
    
    /// Retrieves the App Store receipt data.
    /// - Returns: A result containing the receipt data on success, or an error.
    @available(iOS, deprecated: 15.0, message: "Use getCurrentActiveSubscriptionJWS in InAppModernService on iOS 15+")
    public func getReceiptData() -> Result<Data, Error> {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path)
        else {
            return .failure(InAppStoreKitError.receiptNotFoundNeedRefresh)
        }
        
        do {
            let receiptData = try Data(
                contentsOf: receiptURL, options: Data.ReadingOptions.alwaysMapped)
            return .success(receiptData)
        } catch {
            return .failure(error)
        }
    }
}
