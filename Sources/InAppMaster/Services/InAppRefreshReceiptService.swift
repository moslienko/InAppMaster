//
//  InAppRefreshReceiptService.swift
//  InAppMaster
//
//  Created by Pavel Moslienko on 12.04.2026.
//

import Foundation
import StoreKit

final public class InAppRefreshReceiptService: NSObject {

    // MARK: - Params
    static public let shared = InAppRefreshReceiptService()

    private var receiptRefreshContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Init
    private override init() {}

    // MARK: - Methods
    public func refreshReceipt() async throws {
        if receiptRefreshContinuation != nil {
            throw InAppStoreKitError.pending
        }

        print("starting receipt refresh")

        return try await withCheckedThrowingContinuation { continuation in
            self.receiptRefreshContinuation = continuation

            let request = SKReceiptRefreshRequest(receiptProperties: nil)
            request.delegate = self
            request.start()
        }
    }
}

// MARK: - SKRequestDelegate
extension InAppRefreshReceiptService: SKRequestDelegate {

    public func requestDidFinish(_ request: SKRequest) {
        print("receipt refresh finished")
        receiptRefreshContinuation?.resume()
        receiptRefreshContinuation = nil
    }

    public func request(_ request: SKRequest, didFailWithError error: Error) {
        print("receipt refresh failed: \(error.localizedDescription)")
        receiptRefreshContinuation?.resume(throwing: error)
        receiptRefreshContinuation = nil
    }
}
