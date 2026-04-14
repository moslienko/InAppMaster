<p align="center">
   <img width="200" src="https://moslienko.github.io/Assets/InAppMaster/sdk.png" alt="InAppMaster Logo">
</p>

<p align="center">
   <a href="https://developer.apple.com/swift/">
      <img src="https://img.shields.io/badge/Swift-5.9-orange.svg?style=flat" alt="Swift 5.9">
   </a>
   <a href="https://github.com/apple/swift-package-manager">
      <img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" alt="SPM">
   </a>
</p>

# InAppMaster

<p align="center">
A lightweight library for handling in-app purchases on iOS with a single API for StoreKit 1 and StoreKit 2.
</p>

## Features
- [x] StoreKit 1 support for iOS 13-14
- [x] StoreKit 2 support for iOS 15+
- [x] Product fetching
- [x] Purchase & Restore purchases
- [x] Refresh and reading receipt

## Requirements
- iOS 13.0+
- Swift 5.9+
- Xcode 15+

## Table of Contents

- [InAppMaster](#inappmaster)
  - [Features](#features)
  - [Requirements](#requirements)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
    - [Swift Package Manager](#swift-package-manager)
    - [Manual integration](#manual-integration)
  - [Usage](#usage)
    - [Overview](#overview)
    - [Configure products](#configure-products)
    - [Fetch products](#fetch-products)
    - [Purchase](#purchase)
    - [Restore purchases](#restore-purchases)
    - [Refresh and read receipt](#refresh-and-read-receipt)
      - [Observe transaction updates](#observe-transaction-updates)
    - [Error handling](#error-handling)
  - [License](#license)

## Installation

### Swift Package Manager

Add `InAppMaster` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/moslienko/InAppMaster.git", from: "1.0.0")
]
```

Then add the product to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "InAppMaster", package: "InAppMaster")
    ]
)
```

You can also add the package directly in Xcode via `File` -> `Add Package Dependencies...`.

### Manual integration

If needed, you can integrate the library manually by adding the `Sources/InAppMaster` folder to your project.

## Usage

### Overview

`InAppService` is the main entry point of the library. It automatically chooses the underlying implementation:

- `InAppLegacyService` on iOS 13-14
- `InAppModernService` on iOS 15+

Recommended flow:

1. Configure product identifiers once at app launch.
2. Fetch products from the App Store.
3. Start a purchase for a selected product.
4. Restore purchases when the user requests it.
5. Refresh and read the receipt when you need backend validation.

### Configure products

Configure the service before fetching products or starting a purchase:

```swift
import InAppMaster

let inAppService = InAppService.shared

inAppService.configure(productIdentifiers: [
    "com.example.app.monthly",
    "com.example.app.yearly",
    "com.example.app.lifetime"
])
```

A good place for this call is app startup, for example in `App`, `AppDelegate`, or your dependency container.

### Fetch products

Use `fetchProducts` to request products from the App Store. The result contains `[any InAppProductProtocol]`, so the same code works across StoreKit 1 and StoreKit 2.

```swift
import InAppMaster

InAppService.shared.fetchProducts { result in
    switch result {
    case .success(let products):
        for product in products {
            print(product.id)
            print(product.title)
            print(product.descr)
            print(product.priceString)
        }
    case .failure(let error):
        print("Fetch failed:", error)
    }
}
```

Important: call `fetchProducts` before `purchaseProduct(id:)`. 

### Purchase

```swift
import InAppMaster

InAppService.shared.purchaseProduct(id: "com.example.app.monthly") { result in
    switch result {
    case .success(let productID):
        print("Purchased:", productID)
        // Unlock content or trigger backend validation here.
    case .failure(let error):
        print("Purchase failed:", error)
    }
}
```

### Restore purchases

```swift
import InAppMaster

InAppService.shared.restoreProducts { result in
    switch result {
    case .success(let restoredIDs):
        print("Restored:", restoredIDs)
        // Re-enable premium access based on restored identifiers.
    case .failure(let error):
        print("Restore failed:", error)
    }
}
```

### Refresh and read receipt

Recommended approach:

- iOS 13-14: use `InAppRefreshReceiptService` + `getReceiptData()`
- iOS 15+: prefer `getCurrentActiveSubscriptionJWS()` for StoreKit 2 based backend flows
- iOS 15+: `getReceiptData()` still works if you need the classic App Store receipt

If your backend validates the App Store receipt, refresh it first and then read receipt data from the bundle.

```swift
import InAppMaster

Task {
    do {
        try await InAppRefreshReceiptService.shared.refreshReceipt()

        switch InAppService.shared.getReceiptData() {
        case .success(let receiptData):
            let base64Receipt = receiptData.base64EncodedString()
        case .failure(let error):
            print("Receipt read failed:", error)
        }
    } catch {
        print("Receipt refresh failed:", error)
    }
}
```


 <img src="https://img.shields.io/badge/iOS-15+-blue" alt="iOS 15+">

Use this helper if your backend validates StoreKit 2 transaction JWS instead of the classic app receipt:

```swift
import InAppMaster

if #available(iOS 15.0, *) {
    Task { @MainActor in
        let jws = await InAppService.shared.modernService.getCurrentActiveSubscriptionJWS()
    }
}
```

#### Observe transaction updates
 <img src="https://img.shields.io/badge/iOS-15+-blue" alt="iOS 15+">
 
 StoreKit 2 can deliver verified transactions outside the direct purchase call:

```swift
import InAppMaster

if #available(iOS 15.0, *) {
    Task { @MainActor in
        InAppService.shared.modernService.transactionDidUpdate = { productID in
            print("Transaction updated:", productID)
            // Update local access state or trigger backend revalidation.
        }
    }
}
```

### Error handling

The library may return `InAppStoreKitError` values such as:

- `productsListEmpty`
- `productsNotFetched`
- `unknownProductId`
- `pending`
- `userCancelled`
- `userCantMakePayments`
- `receiptNotFoundNeedRefresh`
- `failedRestore`
- `unknown`

## License

```
InAppMaster
Copyright (c) 2026 Pavel Moslienko 8676976+moslienko@users.noreply.github.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
