//
//  Product+InAppProductProtocol.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 12.04.2026.
//

import StoreKit

@available(iOS 15.0, *)
extension Product: InAppProductProtocol {
   
    public var title: String {
        self.displayName
    }
    
    public var descr: String {
        self.description
    }
    
    public var priceString: String {
        self.displayPrice
    }
    
    public var priceDecimal: Decimal {
        self.price
    }
    
    public var rawSKProduct: SKProduct? {
        nil
    }
    
    @available(iOS 15.0, *)
    public var rawProduct: Product? {
        self
    }
}
