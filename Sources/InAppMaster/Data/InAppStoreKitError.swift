//
//  InAppStoreKitError.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 12.04.2026.
//

public enum InAppStoreKitError: Error {
    case failedRestore
    case pending
    case userCancelled
    case unknownProductId
    case productsListEmpty
    case productsNotFetched
    case userCantMakePayments
    case receiptNotFoundNeedRefresh
    case unknown
}
