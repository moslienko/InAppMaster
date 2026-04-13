//
//  InAppLegacyService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 11.04.2026.
//

import StoreKit

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
        set { productsFetchQueue.async(flags: .barrier) { self._iapProducts = newValue } }
    }

    private var restoredProductIDs: [String] = []

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

    /**
     Инициализация
     - Parameter productIdentifiers: Массив идентификаторов продукта
     **/
    public func configure(productIdentifiers: [String]) {
        self.productIdentifiers = Set(productIdentifiers)
        self.iapProducts = []
    }

    /**
     Можно ли совершить покупку

     - Returns: Разрешил ли пользователь покупки в приложениях
     **/
    public func canMakePurchases() -> Bool {
        SKPaymentQueue.canMakePayments()
    }

    /**
     Покупка
     - Parameter id: Идентификатор продукта
     **/
    public func purchaseMyProduct(id: String) {
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

        print("try puchase \(product.productIdentifier)")

        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }

    /**
     Восстановление покупки
     **/
    public func restorePurchase() {
        guard canMakePurchases() else {
            DispatchQueue.main.async {
                self.productDidFailedRestored?(InAppStoreKitError.userCantMakePayments)
            }
            return
        }
        self.restoredProductIDs = []

        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    /**
     Запрос к доступным продуктам
     **/
    public func fetchAvailableProducts() {
        productsRequest.cancel()
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        productsRequest.delegate = self
        productsRequest.start()
    }

    /**
     Получить информацию о продаваемои товаре
     - Parameter id: Идентификатор продукта
     - Returns: Название товара, локализованная цена и валюта
     **/
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
    /**
     Получение доступных продуктов для покупки
     **/
    public func productsRequest(
        _ request: SKProductsRequest, didReceive response: SKProductsResponse
    ) {
        if response.products.count > 0 {
            iapProducts = response.products
        }

        DispatchQueue.main.async {
            self.productsInfoRequestDidFinished?(response.products)
        }
    }

    /**
     Обработка оплаты
     **/
    public func paymentQueue(
        _ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]
    ) {
        transactions.forEach({ transaction in
            print("status:", transaction.transactionState)
            let productId = transaction.payment.productIdentifier

            switch transaction.transactionState {
            case .purchased:
                SKPaymentQueue.default().finishTransaction(transaction)

                print("successfully purchased")
                DispatchQueue.main.async {
                    self.productDidSuccessPurchased?(productId)
                }
            case .restored:
                SKPaymentQueue.default().finishTransaction(transaction)

                print("restored \(productId)")
                self.restoredProductIDs.append(productId)
            case .failed:
                print("failed - \(transaction.error)")
                SKPaymentQueue.default().finishTransaction(transaction)
                DispatchQueue.main.async {
                    self.productDidFailedPurchased?(transaction.error ?? InAppStoreKitError.unknown)
                }
            case .deferred:  // Ask to Buy
                DispatchQueue.main.async {
                    self.productDidFailedPurchased?(InAppStoreKitError.pending)
                }
            default:
                break
            }
        })
    }

    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        let ids = self.restoredProductIDs
        self.restoredProductIDs = []

        DispatchQueue.main.async {
            if ids.isEmpty {
                self.productDidFailedRestored?(InAppStoreKitError.failedRestore)
            } else {
                self.productDidSuccessRestored?(ids)
            }
        }
    }

    public func paymentQueue(
        _ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error
    ) {
        self.restoredProductIDs = []

        DispatchQueue.main.async {
            self.productDidFailedRestored?(error)
        }
    }

    public func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        true
    }

    public func request(_ request: SKRequest, didFailWithError error: any Error) {
        DispatchQueue.main.async {
            self.productsFetchDidFailed?(error)
        }
    }
}
