//
//  SKProduct+InAppProductProtocol.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 12.04.2026.
//

import StoreKit

extension SKProduct: InAppProductProtocol {
    public var id: String {
        self.productIdentifier
    }
    
    public var title: String {
        self.localizedTitle
    }
    
    public var descr: String {
        self.localizedDescription
    }
    
    public var priceString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = self.priceLocale
        return formatter.string(from: self.price) ?? "\(self.price)"
    }
    
    public var priceDecimal: Decimal {
        self.price.decimalValue
    }
    
    public var rawSKProduct: SKProduct? {
        self
    }
    
    @available(iOS 15.0, *)
    public var rawProduct: Product? {
        nil
    }
}
