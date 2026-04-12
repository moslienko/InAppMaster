//
//  InAppProductProtocol.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 12.04.2026.
//

import Foundation
import StoreKit

public protocol InAppProductProtocol {
    var id: String { get }
    var title: String { get }
    var descr: String { get }
    var priceString: String { get }
    var priceDecimal: Decimal { get }
    
    var rawSKProduct: SKProduct? { get }
    @available(iOS 15.0, *)
    var rawProduct: Product? { get }
}
