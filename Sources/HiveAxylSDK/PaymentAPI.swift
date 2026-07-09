import Foundation
import StoreKit

public final class PaymentAPI: @unchecked Sendable {
    private static let grantPollDelayMilliseconds: [Int64] = [1_000, 2_000, 3_000, 5_000]

    private let lock = NSLock()
    private var client: ConnectClient?

    func bind(client: ConnectClient) {
        lock.lock()
        self.client = client
        lock.unlock()
    }

    func unbind() {
        lock.lock()
        client = nil
        lock.unlock()
    }

    public func listAppStoreProducts(
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        productType: PaymentProductType? = nil
    ) async throws -> [PaymentProduct] {
        if bundleID.isEmpty {
            throw HiveAxylError.invalidArgument("bundleID is required")
        }
        let activeClient = try requireClient()
        var request = Hiveng_V1_ListProductsRequest()
        request.market = .appStore
        request.appIdentifier = bundleID
        if let productType {
            request.productType = productType.protoValue
        }
        let response: Hiveng_V1_ListProductsResponse = try await activeClient.unary(
            "PaymentService", "ListProducts", request
        )
        return response.products.map(PaymentProduct.init(message:))
    }

    public func startAppStorePurchase(
        productID: String,
        productType: PaymentProductType = .oneTime,
        bundleID: String = Bundle.main.bundleIdentifier ?? ""
    ) async throws -> String {
        if productID.isEmpty {
            throw HiveAxylError.invalidArgument("productID is required")
        }
        if bundleID.isEmpty {
            throw HiveAxylError.invalidArgument("bundleID is required")
        }
        let activeClient = try requireClient()
        var request = Hiveng_V1_StartPurchaseRequest()
        request.market = .appStore
        request.productID = productID
        request.productType = productType.protoValue
        request.appIdentifier = bundleID
        let response: Hiveng_V1_StartPurchaseResponse = try await activeClient.unary(
            "PaymentService", "StartPurchase", request
        )
        return response.purchaseIntentID
    }

    public func verifyAppStorePurchase(
        productID: String,
        signedTransactionInfo: String,
        transactionID: String,
        productType: PaymentProductType = .oneTime,
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        purchaseIntentID: String = ""
    ) async throws -> PaymentPurchase {
        if productID.isEmpty {
            throw HiveAxylError.invalidArgument("productID is required")
        }
        if signedTransactionInfo.isEmpty {
            throw HiveAxylError.invalidArgument("signedTransactionInfo is required")
        }
        if transactionID.isEmpty {
            throw HiveAxylError.invalidArgument("transactionID is required")
        }
        if bundleID.isEmpty {
            throw HiveAxylError.invalidArgument("bundleID is required")
        }
        let activeClient = try requireClient()
        var request = Hiveng_V1_VerifyPurchaseRequest()
        request.market = .appStore
        request.receiptPayload = signedTransactionInfo
        request.productID = productID
        request.productType = productType.protoValue
        request.purchaseToken = transactionID
        request.appIdentifier = bundleID
        request.purchaseIntentID = purchaseIntentID
        let response: Hiveng_V1_VerifyPurchaseResponse = try await activeClient.unary(
            "PaymentService", "VerifyPurchase", request
        )
        guard response.hasPurchase else {
            throw HiveAxylError.transport("verify purchase response missing purchase")
        }
        return PaymentPurchase(message: response.purchase)
    }

    @available(iOS 15.0, macOS 12.0, *)
    public func purchaseAppStoreProduct(
        productID: String,
        productType: PaymentProductType = .oneTime,
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        waitForGrant: Bool = true,
        grantTimeoutMilliseconds: Int64 = 30_000
    ) async throws -> PaymentPurchase {
        let purchaseIntentID = try await startAppStorePurchase(
            productID: productID,
            productType: productType,
            bundleID: bundleID
        )
        let products = try await Product.products(for: [productID])
        guard let product = products.first(where: { item in item.id == productID }) else {
            throw HiveAxylError.transport("app store product not found")
        }
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let signedTransactionInfo = verification.jwsRepresentation
            let transaction = try Self.verifiedTransaction(verification)
            return try await verifyAppStoreTransaction(
                transaction,
                signedTransactionInfo: signedTransactionInfo,
                productType: productType,
                bundleID: bundleID,
                purchaseIntentID: purchaseIntentID,
                waitForGrant: waitForGrant,
                grantTimeoutMilliseconds: grantTimeoutMilliseconds
            )
        case .pending:
            throw HiveAxylError.transport("app store purchase pending")
        case .userCancelled:
            throw HiveAxylError.transport("app store purchase cancelled")
        @unknown default:
            throw HiveAxylError.transport("unknown app store purchase result")
        }
    }

    @available(iOS 15.0, macOS 12.0, *)
    public func syncUnfinishedAppStorePurchases(
        productTypes: [String: PaymentProductType] = [:],
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        waitForGrant: Bool = true,
        grantTimeoutMilliseconds: Int64 = 30_000
    ) async throws -> [PaymentPurchase] {
        if bundleID.isEmpty {
            throw HiveAxylError.invalidArgument("bundleID is required")
        }
        var purchases: [PaymentPurchase] = []
        for await result in Transaction.unfinished {
            let transaction = try Self.verifiedTransaction(result)
            let productType = productTypes[transaction.productID]
                ?? Self.paymentProductType(transaction.productType)
            let purchase = try await verifyAppStoreTransaction(
                transaction,
                signedTransactionInfo: result.jwsRepresentation,
                productType: productType,
                bundleID: bundleID,
                purchaseIntentID: "",
                waitForGrant: waitForGrant,
                grantTimeoutMilliseconds: grantTimeoutMilliseconds
            )
            purchases.append(purchase)
        }
        return purchases
    }

    public func getPurchase(purchaseID: String) async throws -> PaymentPurchase {
        if purchaseID.isEmpty {
            throw HiveAxylError.invalidArgument("purchaseID is required")
        }
        let activeClient = try requireClient()
        var request = Hiveng_V1_PaymentServiceGetPurchaseRequest()
        request.purchaseID = purchaseID
        let response: Hiveng_V1_PaymentServiceGetPurchaseResponse = try await activeClient.unary(
            "PaymentService", "GetPurchase", request
        )
        guard response.hasPurchase else {
            throw HiveAxylError.transport("get purchase response missing purchase")
        }
        return PaymentPurchase(message: response.purchase)
    }

    public func waitForPaymentGrant(
        purchaseID: String,
        timeoutMilliseconds: Int64 = 30_000
    ) async throws -> PaymentPurchase {
        if purchaseID.isEmpty {
            throw HiveAxylError.invalidArgument("purchaseID is required")
        }
        if timeoutMilliseconds <= 0 {
            throw HiveAxylError.invalidArgument("timeoutMilliseconds must be positive")
        }
        let startedAt = Date()
        var purchase = try await getPurchase(purchaseID: purchaseID)
        if isGrantFinished(purchase) || isPurchaseFailed(purchase) {
            return purchase
        }
        var delayIndex = 0
        var elapsed = elapsedMilliseconds(since: startedAt)
        while elapsed < timeoutMilliseconds {
            let remainingMilliseconds = timeoutMilliseconds - elapsed
            let delayMilliseconds = min(nextDelayMilliseconds(delayIndex), remainingMilliseconds)
            try await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            purchase = try await getPurchase(purchaseID: purchaseID)
            if isGrantFinished(purchase) || isPurchaseFailed(purchase) {
                return purchase
            }
            delayIndex += 1
            elapsed = elapsedMilliseconds(since: startedAt)
        }
        return purchase
    }

    private func requireClient() throws -> ConnectClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client else {
            throw HiveAxylError.transport("discovery returned no endpoint for domain: payment")
        }
        return client
    }

    @available(iOS 15.0, macOS 12.0, *)
    private func verifyAppStoreTransaction(
        _ transaction: Transaction,
        signedTransactionInfo: String,
        productType: PaymentProductType,
        bundleID: String,
        purchaseIntentID: String,
        waitForGrant: Bool,
        grantTimeoutMilliseconds: Int64
    ) async throws -> PaymentPurchase {
        do {
            let purchase = try await verifyAppStorePurchase(
                productID: transaction.productID,
                signedTransactionInfo: signedTransactionInfo,
                transactionID: String(transaction.id),
                productType: productType,
                bundleID: bundleID,
                purchaseIntentID: purchaseIntentID
            )
            if !waitForGrant {
                await transaction.finish()
                return purchase
            }
            let updated = try await waitForPaymentGrant(
                purchaseID: purchase.id,
                timeoutMilliseconds: grantTimeoutMilliseconds
            )
            if isGrantFinished(updated) || isPurchaseFailed(updated) {
                await transaction.finish()
            }
            return updated
        } catch HiveAxylError.duplicateReceipt {
            await transaction.finish()
            throw HiveAxylError.duplicateReceipt
        }
    }

    private static func nextDelayMilliseconds(_ index: Int) -> Int64 {
        if index < grantPollDelayMilliseconds.count {
            return grantPollDelayMilliseconds[index]
        }
        return grantPollDelayMilliseconds.last ?? 5_000
    }

    private func nextDelayMilliseconds(_ index: Int) -> Int64 {
        Self.nextDelayMilliseconds(index)
    }

    @available(iOS 15.0, macOS 12.0, *)
    private static func verifiedTransaction(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case let .verified(transaction):
            return transaction
        case let .unverified(_, error):
            throw HiveAxylError.transport("unverified app store transaction: \(error.localizedDescription)")
        }
    }

    @available(iOS 15.0, macOS 12.0, *)
    private static func paymentProductType(_ productType: Product.ProductType) -> PaymentProductType {
        if productType == .autoRenewable || productType == .nonRenewable {
            return .subscription
        }
        return .oneTime
    }
}

private extension PaymentProductType {
    var protoValue: Hiveng_V1_ProductType {
        switch self {
        case .oneTime:
            return .oneTime
        case .subscription:
            return .subscription
        }
    }
}

private func elapsedMilliseconds(since date: Date) -> Int64 {
    Int64(Date().timeIntervalSince(date) * 1_000)
}

private func isGrantFinished(_ purchase: PaymentPurchase) -> Bool {
    purchase.grantStatus == "delivered"
        || purchase.grantStatus == "not_required"
        || purchase.grantStatus == "client_pending"
}

private func isPurchaseFailed(_ purchase: PaymentPurchase) -> Bool {
    ["failed", "canceled", "refunded", "expired"].contains(purchase.status)
}
