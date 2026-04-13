//
//  InAppModernService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 11.04.2026.
//

import StoreKit

/// StoreKit 2 (iOS 15+)
@available(iOS 15.0, *)
@MainActor
final public class InAppModernService {
    
    // MARK: - Params
    static public let shared = InAppModernService()
    
    private var iapProducts = [Product]()
    private var updatesTask: Task<Void, Never>?
    private var finishedTransactionIDs = Set<UInt64>()
    
    // MARK: - Callbacks
    public var transactionDidUpdate: ((String) -> Void)?
    
    // MARK: - Init
    private init() {
        // External events
        updatesTask = Task { @MainActor in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                
                if !finishedTransactionIDs.contains(transaction.id) {
                    finishedTransactionIDs.insert(transaction.id)
                    await transaction.finish()
                    transactionDidUpdate?(transaction.productID)
                }
            }
        }
    }
    
    // MARK: - Methods
    
    /// Initiates a purchase for the product.
    /// - Parameter id: The identifier of the product to be purchased.
    public func purchaseMyProduct(id: String) async throws {
        guard !iapProducts.isEmpty else {
            throw InAppStoreKitError.productsNotFetched
        }
        guard let product = iapProducts.first(where: { $0.id == id }) else {
            throw InAppStoreKitError.unknownProductId
        }
        
        let result = try await product.purchase()
        
        switch result {
        case let .success(.verified(transaction)):
            if !finishedTransactionIDs.contains(transaction.id) {
                finishedTransactionIDs.insert(transaction.id)
                await transaction.finish()
                transactionDidUpdate?(transaction.productID)
            }
        case let .success(.unverified(_, error)):
            throw error
        case .pending:
            throw InAppStoreKitError.pending
        case .userCancelled:
            throw InAppStoreKitError.userCancelled
        @unknown default:
            throw InAppStoreKitError.unknown
        }
    }
    
    /// Restores previously purchased products.
    /// - Returns: A set of product identifiers for currently active purchases.
    public func restorePurchase() async throws -> Set<String> {
        var purchasedProductIDs: Set<String> = []
        
        try await AppStore.sync()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                if let expDate = transaction.expirationDate {
                    if expDate > Date() { purchasedProductIDs.insert(transaction.productID) }
                } else {
                    purchasedProductIDs.insert(transaction.productID)
                }
            }
        }
        
        return purchasedProductIDs
    }
    
    /// Fetches the available in-app products from the App Store.
    /// - Parameter productIdentifiers: The product identifiers to fetch.
    /// - Returns: An array of products matching the provided identifiers.
    public func fetchAvailableProducts(
        productIdentifiers: [String]
    ) async throws -> [any InAppProductProtocol] {
        let identifiers = Set(productIdentifiers)
        guard !identifiers.isEmpty else {
            throw InAppStoreKitError.productsListEmpty
        }
        
        let products = try await Product.products(for: identifiers)
        self.iapProducts = products
        
        return products
    }
    
    /// Returns the App Store product.
    /// - Parameter id: The identifier of the product.
    /// - Returns: The matching App Store product, or `nil` if not found.
    public func getProduct(id: String) -> Product? {
        iapProducts.first(where: { $0.id == id })
    }
    
    /// Refreshes the App Store receipt if it is missing from the bundle.
    public func refreshReceiptIfNeeded() async throws {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            try await InAppRefreshReceiptService.shared.refreshReceipt()
            return
        }
        
        if !FileManager.default.fileExists(atPath: receiptURL.path) {
            try await InAppRefreshReceiptService.shared.refreshReceipt()
        }
    }
    
    /// Returns the JWS representation of the currently active subscription.
    /// - Returns: The JWS string of the active subscription, or `nil` if none is active.
    public func getCurrentActiveSubscriptionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantFuture) > Date() {
                return result.jwsRepresentation
            }
        }
        return nil
    }
}
