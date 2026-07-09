import Foundation
import SwiftProtobuf
import XCTest
@testable import HiveAxylSDK

final class PaymentTests: XCTestCase {
    func testAppStorePurchaseFlowRequestsUseAppStoreFields() async throws {
        let router = MockRouter()
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "player-token")
        let state = LockedCounter()
        router.onRequest { request in
            if request.path == "/hiveng.v1.DiscoveryService/ResolveEndpoints" {
                var response = Hiveng_V1_ResolveEndpointsResponse()
                var auth = Hiveng_V1_EndpointEntry()
                auth.domain = "auth"
                auth.baseURL = TestSupport.authBaseUrl
                var payment = Hiveng_V1_EndpointEntry()
                payment.domain = "payment"
                payment.baseURL = "https://payment.test.hive-axyl"
                response.endpoints = [auth, payment]
                response.ttlSeconds = 300
                return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
            }
            XCTAssertEqual(request.authorization, "Bearer test-api-key")
            XCTAssertEqual(request.playerToken, "player-token")
            switch state.next() {
            case 0:
                XCTAssertEqual(request.path, "/hiveng.v1.PaymentService/ListProducts")
                let decoded = try Hiveng_V1_ListProductsRequest(serializedBytes: request.body)
                XCTAssertEqual(decoded.market, .appStore)
                XCTAssertEqual(decoded.appIdentifier, "com.hiveaxyl.iosgame")
                var product = Hiveng_V1_PaymentProduct()
                product.market = .appStore
                product.appIdentifier = "com.hiveaxyl.iosgame"
                product.productID = "ios_item_01"
                product.productType = .oneTime
                product.marketStatus = "active"
                product.title = "Item 1"
                product.enabled = true
                var response = Hiveng_V1_ListProductsResponse()
                response.products = [product]
                return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
            case 1:
                XCTAssertEqual(request.path, "/hiveng.v1.PaymentService/StartPurchase")
                let decoded = try Hiveng_V1_StartPurchaseRequest(serializedBytes: request.body)
                XCTAssertEqual(decoded.market, .appStore)
                XCTAssertEqual(decoded.productID, "ios_item_01")
                XCTAssertEqual(decoded.productType, .oneTime)
                XCTAssertEqual(decoded.appIdentifier, "com.hiveaxyl.iosgame")
                var response = Hiveng_V1_StartPurchaseResponse()
                response.purchaseIntentID = "intent-1"
                return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
            default:
                XCTAssertEqual(request.path, "/hiveng.v1.PaymentService/VerifyPurchase")
                let decoded = try Hiveng_V1_VerifyPurchaseRequest(serializedBytes: request.body)
                XCTAssertEqual(decoded.market, .appStore)
                XCTAssertEqual(decoded.productID, "ios_item_01")
                XCTAssertEqual(decoded.productType, .oneTime)
                XCTAssertEqual(decoded.purchaseToken, "200000000000001")
                XCTAssertEqual(decoded.receiptPayload, "signed-jws")
                XCTAssertEqual(decoded.appIdentifier, "com.hiveaxyl.iosgame")
                XCTAssertEqual(decoded.purchaseIntentID, "intent-1")
                var purchase = Hiveng_V1_Purchase()
                purchase.id = "purchase-1"
                purchase.market = .appStore
                purchase.productType = .oneTime
                purchase.productID = "ios_item_01"
                purchase.packageName = "com.hiveaxyl.iosgame"
                purchase.status = .verified
                purchase.marketOrderID = "200000000000001"
                var response = Hiveng_V1_VerifyPurchaseResponse()
                response.purchase = purchase
                return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
            }
        }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let products = try await hive.payment.listAppStoreProducts(bundleID: "com.hiveaxyl.iosgame")
        let intentID = try await hive.payment.startAppStorePurchase(
            productID: "ios_item_01",
            bundleID: "com.hiveaxyl.iosgame"
        )
        let purchase = try await hive.payment.verifyAppStorePurchase(
            productID: "ios_item_01",
            signedTransactionInfo: "signed-jws",
            transactionID: "200000000000001",
            bundleID: "com.hiveaxyl.iosgame",
            purchaseIntentID: intentID
        )

        XCTAssertEqual(products.first?.productID, "ios_item_01")
        XCTAssertEqual(intentID, "intent-1")
        XCTAssertEqual(purchase.market, "app_store")
        XCTAssertEqual(purchase.marketOrderID, "200000000000001")
    }
}
