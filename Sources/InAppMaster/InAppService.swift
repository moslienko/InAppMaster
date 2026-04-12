//
//  InAppService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 11.04.2026.
//

import StoreKit

final public class InAppService: NSObject {
    
    // MARK: - Params
    static public let shared = InAppService()
    
    public var productIdentifiers: Set<String> = []
    
    private var productsRequest = SKProductsRequest()
    private var iapProducts = [SKProduct]()
    
    // MARK: - Callbacks
    public var productDidSuccessPurchased: ((String) -> Void)?
    public var productDidFailedPurchased: ((Error?) -> Void)?
    public var productsInfoRequestDidFinished: (([SKProduct]) -> Void)?
    
    // MARK: - Init
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    /**
     Инициализация
     - Parameter productIdentifiers: Массив идентификаторов продукта
     **/
    public func configure(productIdentifiers: [String]) {
        self.productIdentifiers = Set(productIdentifiers)
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
        if iapProducts.count == 0 { return }
        
        if let product = iapProducts.first(where: { $0.productIdentifier == id }),
           self.canMakePurchases() {
            print("try puchase \(product.productIdentifier)")
            
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(payment)
        } else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(nil)
            }
        }
    }
    
    /**
     Восстановление покупки
     **/
    public func restorePurchase() {
        guard canMakePurchases() else {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(nil)
            }
            return
        }
        
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
    public func getProductInfo(id: String) -> (name: String, price: NSDecimalNumber, currency: String)? {
        guard let product = iapProducts.first(where: { $0.productIdentifier == id }) else { return nil }
        
        return (
            name: product.localizedTitle, price: product.price,
            currency: product.priceLocale.currencySymbol ?? "$"
        )
    }
}

extension InAppService: SKProductsRequestDelegate,
                        SKPaymentTransactionObserver
{
    /**
     Получение доступных продуктов для покупки
     **/
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
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
            switch transaction.transactionState {
            case .purchased, .restored:
                SKPaymentQueue.default().finishTransaction(transaction)
                
                print("successfully purchased or restored")
                DispatchQueue.main.async {
                    self.productDidSuccessPurchased?(transaction.payment.productIdentifier)
                }
            case .failed:
                print("failed - \(transaction.error)")
                SKPaymentQueue.default().finishTransaction(transaction)
                DispatchQueue.main.async {
                    self.productDidFailedPurchased?(transaction.error)
                }
            default:
                break
            }
        })
    }
    
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        if queue.transactions.isEmpty {
            DispatchQueue.main.async {
                self.productDidFailedPurchased?(nil)
            }
        }
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        DispatchQueue.main.async {
            self.productDidFailedPurchased?(error)
        }
    }
}
