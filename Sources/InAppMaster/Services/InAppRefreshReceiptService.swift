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
    private var receiptRefreshRequest: SKReceiptRefreshRequest?

    // MARK: - Init
    private override init() {}

    // MARK: - Methods
    
    /// Refreshes the App Store receipt.
    public func refreshReceipt() async throws {
        if receiptRefreshContinuation != nil {
            throw InAppStoreKitError.pending
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.receiptRefreshContinuation = continuation

            let request = SKReceiptRefreshRequest(receiptProperties: nil)
            request.delegate = self
            self.receiptRefreshRequest = request
            request.start()
        }
    }
}

// MARK: - SKRequestDelegate
extension InAppRefreshReceiptService: SKRequestDelegate {

    /// Called when the receipt refresh request finishes successfully.
    /// - Parameter request: The request that finished.
    public func requestDidFinish(_ request: SKRequest) {
        receiptRefreshContinuation?.resume()
        receiptRefreshContinuation = nil
        receiptRefreshRequest = nil
    }

    /// Called when the receipt refresh request fails.
    /// - Parameters:
    ///   - request: The request that failed.
    ///   - error: The error describing the failure.
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        receiptRefreshContinuation?.resume(throwing: error)
        receiptRefreshContinuation = nil
        receiptRefreshRequest = nil
    }
}
