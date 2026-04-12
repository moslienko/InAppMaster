//
//  InAppModernService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 11.04.2026.
//

import StoreKit

@available(iOS 15.0, *)
@MainActor
final public class InAppModernService {
    
    // MARK: - Params
    static public let shared = InAppModernService()
    
    public private(set) var productIdentifiers: Set<String> = []
    
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
    
    /**
     Инициализация
     - Parameter productIdentifiers: Массив идентификаторов продукта
     **/
    public func configure(productIdentifiers: [String]) {
        self.productIdentifiers = Set(productIdentifiers)
        self.iapProducts = []
        
    }
    
    /**
     Покупка
     - Parameter id: Идентификатор продукта
     **/
    public func purchaseMyProduct(id: String) async throws {
        guard !iapProducts.isEmpty else {
            throw InAppStoreKitError.productsNotFetched
        }
        guard let product = iapProducts.first(where: { $0.id == id }) else {
            throw InAppStoreKitError.unknownProductId
        }
        
        print("try puchase \(product.id)")
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
    
    /**
     Восстановление покупки
     **/
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
    
    /**
     Запрос к доступным продуктам
     **/
    public func fetchAvailableProducts() async throws -> [Product] {
        guard !productIdentifiers.isEmpty else {
            throw InAppStoreKitError.productsListEmpty
        }
        
        let products = try await Product.products(for: productIdentifiers)
        self.iapProducts = products
        
        return products
    }
    
    /**
     Получить продукт
     - Parameter id: Идентификатор продукта
     - Returns: App Store продукт
     **/
    public func getProduct(id: String) -> Product? {
        iapProducts.first(where: { $0.id == id })
    }
}
