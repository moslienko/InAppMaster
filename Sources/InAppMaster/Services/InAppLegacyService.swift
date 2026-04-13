//
//  InAppLegacyService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 11.04.2026.
//

import StoreKit

/// StoreKit 1 (iOS 13-14)
final public class InAppLegacyService: NSObject {
    
    // MARK: - Params
    static public let shared = InAppLegacyService()
    
    private var productsRequest = SKProductsRequest()
    private let productsFetchQueue = DispatchQueue(
        label: "com.InAppMaster.products", attributes: .concurrent)
    private var _iapProducts = [SKProduct]()
    
    public private(set) var productIdentifiers: Set<String> = []
    public var iapProducts: [SKProduct] {
        get { productsFetchQueue.sync { _iapProducts } }
        set { productsFetchQueue.sync(flags: .barrier) { self._iapProducts = newValue } }
    }
    
    private var restoredProductIDs: [String] = []
    public private(set) var isPurchaseInProgress = false
    public private(set) var isRestoreInProgress = false
    
    // MARK: - Callbacks
    public var productDidSuccessPurchased: ((String) -> Void)?
    public var productDidFailedPurchased: ((Error) -> Void)?
    public var productDidSuccessRestored: (([String]) -> Void)?
    public var productDidFailedRestored: ((Error) -> Void)?
    public var productsFetchDidFailed: ((Error) -> Void)?
    public var productsInfoRequestDidFinished: (([any InAppProductProtocol]) -> Void)?
    
    // MARK: - Init
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    // MARK: - Methods
    
    /// Configures the service with the given product identifiers.
    /// - Parameter productIdentifiers: The array of product identifiers to be loaded.
    public func configure(productIdentifiers: [String]) {
        self.productIdentifiers = Set(productIdentifiers)
        self.iapProducts = []
    }
    
    /// Indicates whether the user is allowed to make in-app purchases.
    /// - Returns: `true` if the user has enabled in-app purchases, otherwise `false`.
    public func canMakePurchases() -> Bool {
        SKPaymentQueue.canMakePayments()
    }
    
    /// Initiates a purchase for the product with the given identifier.
    /// - Parameter id: The identifier of the product to be purchased.
    public func purchaseMyProduct(id: String) {
        guard !isPurchaseInProgress else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.pending)
            }
            return
        }
        guard !iapProducts.isEmpty else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.productsNotFetched)
            }
            return
        }
        guard let product = iapProducts.first(where: { $0.productIdentifier == id }) else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.unknownProductId)
            }
            return
        }
        
        guard canMakePurchases() else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.userCantMakePayments)
            }
            return
        }
        
        isPurchaseInProgress = true
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    /// Restores previously completed purchases.
    public func restorePurchase() {
        guard !isRestoreInProgress else {
            DispatchQueue.main.async {
                self.productDidFailedRestored?(InAppStoreKitError.pending)
            }
            return
        }
        guard canMakePurchases() else {
            DispatchQueue.main.async {
                self.productDidFailedRestored?(InAppStoreKitError.userCantMakePayments)
            }
            return
        }
        isRestoreInProgress = true
        self.restoredProductIDs = []
        
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    /// Fetch the available products info.
    public func fetchAvailableProducts() {
        productsRequest.cancel()
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        productsRequest.delegate = self
        productsRequest.start()
    }
    
    /// Returns information about a product available for purchase.
    /// - Parameter id: The identifier of the product.
    /// - Returns: A tuple with the localized title, price and currency symbol, or `nil` if the product is not found.
    public func getProductInfo(id: String) -> (
        name: String, price: NSDecimalNumber, currency: String
    )? {
        guard let product = iapProducts.first(where: { $0.productIdentifier == id }) else {
            return nil
        }
        
        return (
            name: product.localizedTitle, price: product.price,
            currency: product.priceLocale.currencySymbol ?? "$"
        )
    }
}

extension InAppLegacyService: SKProductsRequestDelegate, SKPaymentTransactionObserver {
    /// Handles the App Store response containing the list of available products.
    /// - Parameters:
    ///   - request: The products request that produced the response.
    ///   - response: The response containing the available products.
    public func productsRequest(
        _ request: SKProductsRequest, didReceive response: SKProductsResponse
    ) {
        if response.products.isEmpty {
            DispatchQueue.main.async {
                self.productsFetchDidFailed?(InAppStoreKitError.productsListEmpty)
            }
        } else {
            iapProducts = response.products
            DispatchQueue.main.async {
                self.productsInfoRequestDidFinished?(response.products)
            }
        }
    }
    
    /// Handles updates for transactions in the payment queue.
    /// - Parameters:
    ///   - queue: The payment queue that updated the transactions.
    ///   - transactions: The transactions whose state has changed.
    public func paymentQueue(
        _ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]
    ) {
        transactions.forEach({ transaction in
            let productId = transaction.payment.productIdentifier
            
            switch transaction.transactionState {
            case .purchased:
                SKPaymentQueue.default().finishTransaction(transaction)
                isPurchaseInProgress = false
                
                DispatchQueue.main.async {
                    self.productDidSuccessPurchased?(productId)
                }
            case .restored:
                SKPaymentQueue.default().finishTransaction(transaction)
                
                self.restoredProductIDs.append(productId)
            case .failed:
                SKPaymentQueue.default().finishTransaction(transaction)
                isPurchaseInProgress = false
                DispatchQueue.main.async {
                    if let skError = transaction.error as? SKError,
                       skError.code == .paymentCancelled {
                        self.productDidFailedPurchased?(InAppStoreKitError.userCancelled)
                    } else {
                        self.productDidFailedPurchased?(transaction.error ?? InAppStoreKitError.unknown)
                    }
                }
            case .deferred:  // Ask to Buy
                isPurchaseInProgress = false
                DispatchQueue.main.async {
                    self.productDidFailedPurchased?(InAppStoreKitError.pending)
                }
            default:
                break
            }
        })
    }
    
    /// Called when restoring completed transactions has finished.
    /// - Parameter queue: The payment queue that finished restoring transactions.
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        let ids = self.restoredProductIDs
        self.restoredProductIDs = []
        isRestoreInProgress = false
        
        DispatchQueue.main.async {
            if ids.isEmpty {
                self.productDidFailedRestored?(InAppStoreKitError.failedRestore)
            } else {
                self.productDidSuccessRestored?(ids)
            }
        }
    }
    
    /// Called when restoring completed transactions fails.
    /// - Parameters:
    ///   - queue: The payment queue that failed to restore transactions.
    ///   - error: The error describing the failure.
    public func paymentQueue(
        _ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error
    ) {
        self.restoredProductIDs = []
        isRestoreInProgress = false
        
        DispatchQueue.main.async {
            self.productDidFailedRestored?(error)
        }
    }
    
    /// Determines whether a store-initiated payment should be added to the payment queue.
    /// - Parameters:
    ///   - queue: The payment queue receiving the payment.
    ///   - payment: The payment requested from the App Store.
    ///   - product: The product associated with the payment.
    /// - Returns: `true` to proceed with the payment, otherwise `false`.
    public func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        true
    }
    
    /// Called when a StoreKit request fails.
    /// - Parameters:
    ///   - request: The request that failed.
    ///   - error: The error describing the failure.
    public func request(_ request: SKRequest, didFailWithError error: any Error) {
        DispatchQueue.main.async {
            self.productsFetchDidFailed?(error)
        }
    }
}
