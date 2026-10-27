//
//  InAppLegacyService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 11.04.2026.
//

import StoreKit

/// StoreKit 1 (iOS 13-14)
final class InAppLegacyService: NSObject {
    
    // MARK: - Params
    static let shared = InAppLegacyService()
    
    private var productsRequest = SKProductsRequest()
    private let productsFetchQueue = DispatchQueue(
        label: "com.InAppMaster.products", attributes: .concurrent)
    private var _iapProducts = [SKProduct]()
    
    private(set) var productIdentifiers: Set<String> = []
    var iapProducts: [SKProduct] {
        get { productsFetchQueue.sync { _iapProducts } }
        set { productsFetchQueue.sync(flags: .barrier) { self._iapProducts = newValue } }
    }
    
    private var purchaseProductRequest: SKProductsRequest?
    private var pendingPurchaseProductId: String?
    
    private var restoredProductIDs: [String] = []
    private(set) var isPurchaseInProgress = false
    private(set) var isRestoreInProgress = false
    
    // MARK: - Callbacks
    var productDidSuccessPurchased: ((String) -> Void)?
    var productDidFailedPurchased: ((Error) -> Void)?
    var productDidSuccessRestored: (([String]) -> Void)?
    var productDidFailedRestored: ((Error) -> Void)?
    var productsFetchDidFailed: ((Error) -> Void)?
    var productsInfoRequestDidFinished: (([any InAppProductProtocol]) -> Void)?
    
    // MARK: - Init
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    // MARK: - Methods
    
    /// Configures the service with the given product identifiers.
    /// - Parameter productIdentifiers: The array of product identifiers to be loaded.
    func configure(productIdentifiers: [String]) {
        self.productIdentifiers = Set(productIdentifiers)
        self.iapProducts = []
    }
    
    /// Indicates whether the user is allowed to make in-app purchases.
    /// - Returns: `true` if the user has enabled in-app purchases, otherwise `false`.
    func canMakePurchases() -> Bool {
        SKPaymentQueue.canMakePayments()
    }
    
    /// Initiates a purchase for the product with the given identifier.
    /// - Parameter id: The identifier of the product to be purchased.
    func purchaseMyProduct(id: String) {
        guard !isPurchaseInProgress else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.pending)
            }
            return
        }
        guard canMakePurchases() else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.userCantMakePayments)
            }
            return
        }
        
        if let product = iapProducts.first(where: { $0.productIdentifier == id }) {
            startPayment(for: product)
        } else {
            fetchProductForPurchase(id: id)
        }
    }
    
    /// Restores previously completed purchases.
    func restorePurchase() {
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
    func fetchAvailableProducts() {
        productsRequest.cancel()
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        productsRequest.delegate = self
        productsRequest.start()
    }
    
}

extension InAppLegacyService: SKProductsRequestDelegate, SKPaymentTransactionObserver {
    /// Handles the App Store response containing the list of available products.
    /// - Parameters:
    ///   - request: The products request that produced the response.
    ///   - response: The response containing the available products.
    func productsRequest(
        _ request: SKProductsRequest, didReceive response: SKProductsResponse
    ) {
        if request === purchaseProductRequest {
            handlePurchaseProductResponse(response.products)
            return
        }
        
        if response.products.isEmpty {
            DispatchQueue.main.async {
                self.productsFetchDidFailed?(InAppStoreKitError.productsListEmpty)
            }
        } else {
            mergeIntoCache(response.products)
            DispatchQueue.main.async {
                self.productsInfoRequestDidFinished?(response.products)
            }
        }
    }
    
    /// Handles updates for transactions in the payment queue.
    /// - Parameters:
    ///   - queue: The payment queue that updated the transactions.
    ///   - transactions: The transactions whose state has changed.
    func paymentQueue(
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
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
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
    func paymentQueue(
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
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        true
    }
    
    /// Called when a StoreKit request fails.
    /// - Parameters:
    ///   - request: The request that failed.
    ///   - error: The error describing the failure.
    func request(_ request: SKRequest, didFailWithError error: any Error) {
        if request === purchaseProductRequest {
            handlePurchaseProductResponse([])
            return
        }
        
        DispatchQueue.main.async {
            self.productsFetchDidFailed?(error)
        }
    }
}

// MARK: - Helpers
private extension InAppLegacyService {
    
    /// Adds the payment for the product to the payment queue.
    /// - Parameter product: The product to be purchased.
    func startPayment(for product: SKProduct) {
        isPurchaseInProgress = true
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    /// Loads the product from the App Store before the purchase.
    /// - Parameter id: The identifier of the product to be purchased.
    func fetchProductForPurchase(id: String) {
        isPurchaseInProgress = true
        pendingPurchaseProductId = id
        
        let request = SKProductsRequest(productIdentifiers: [id])
        request.delegate = self
        purchaseProductRequest = request
        request.start()
    }
    
    /// Handles the App Store response for the product requested before the purchase.
    /// - Parameter products: The products received from the App Store.
    func handlePurchaseProductResponse(_ products: [SKProduct]) {
        let id = pendingPurchaseProductId
        purchaseProductRequest = nil
        pendingPurchaseProductId = nil
        mergeIntoCache(products)
        
        // Store is unavailable
        guard !iapProducts.isEmpty else {
            isPurchaseInProgress = false
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.productsNotFetched)
            }
            return
        }
        guard let product = iapProducts.first(where: { $0.productIdentifier == id }) else {
            isPurchaseInProgress = false
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(InAppStoreKitError.unknownProductId)
            }
            return
        }
        
        startPayment(for: product)
    }
    
    /// Adds the products to the cache without removing already loaded ones.
    /// - Parameter products: The products to be added.
    func mergeIntoCache(_ products: [SKProduct]) {
        productsFetchQueue.sync(flags: .barrier) {
            for product in products {
                if let index = self._iapProducts.firstIndex(where: { $0.productIdentifier == product.productIdentifier }) {
                    self._iapProducts[index] = product
                } else {
                    self._iapProducts.append(product)
                }
            }
        }
    }
}
