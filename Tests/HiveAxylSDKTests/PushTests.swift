import Foundation
import SwiftProtobuf
import XCTest
@testable import HiveAxylSDK

final class PushTests: XCTestCase {
    func testRegisterPushTargetSendsIosPayload() async throws {
        let router = MockRouter()
        var response = Hiveng_V1_RegisterPushTargetResponse()
        response.target = pushTarget()
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.RemotePushService/RegisterPushTarget")
            XCTAssertEqual(request.authorization, "Bearer test-api-key")
            XCTAssertEqual(request.playerToken, "access-1")
            let decoded = try Hiveng_V1_RegisterPushTargetRequest(serializedBytes: request.body)
            XCTAssertEqual(decoded.fid, "fid-1")
            XCTAssertEqual(decoded.fcmToken, "fcm-token-1")
            XCTAssertEqual(decoded.appIdentifier, "com.hiveaxyl.sample")
            XCTAssertEqual(decoded.platform, "ios")
            return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-1")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let target = try await hive.push.registerPushTarget(
            fid: "fid-1",
            fcmToken: "fcm-token-1",
            appIdentifier: "com.hiveaxyl.sample"
        )

        XCTAssertEqual(target.id, "target-1")
        XCTAssertEqual(target.platform, "ios")
        XCTAssertEqual(target.tokenPreview, "abcd...1234")
    }

    func testDeletePushTargetSendsFid() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.RemotePushService/DeletePushTarget")
            XCTAssertEqual(request.playerToken, "access-1")
            let decoded = try Hiveng_V1_DeletePushTargetRequest(serializedBytes: request.body)
            XCTAssertEqual(decoded.fid, "fid-1")
            return StubResponse(
                statusCode: 200,
                body: try TestSupport.proto(Hiveng_V1_DeletePushTargetResponse())
            )
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-1")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        try await hive.push.deletePushTarget(fid: "fid-1")
    }

    func testRegisterPushTargetFailsWhenEndpointMissing() async throws {
        let router = MockRouter()
        router.onRequest { request in
            XCTAssertEqual(request.path, "/hiveng.v1.DiscoveryService/ResolveEndpoints")
            var response = Hiveng_V1_ResolveEndpointsResponse()
            var entry = Hiveng_V1_EndpointEntry()
            entry.domain = "auth"
            entry.baseURL = TestSupport.authBaseUrl
            response.endpoints = [entry]
            return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
        }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        do {
            _ = try await hive.push.registerPushTarget(fid: "fid-1", fcmToken: "token")
            XCTFail("expected transport error")
        } catch let error as HiveAxylError {
            guard case let .transport(message) = error else {
                return XCTFail("expected transport, got \(error)")
            }
            XCTAssertTrue(message.contains("remote_push"))
        }
    }

    func testEmptyFidThrowsInvalidArgument() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { _ in StubResponse(statusCode: 200, body: Data()) }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        do {
            _ = try await hive.push.registerPushTarget(fid: "")
            XCTFail("expected invalidArgument")
        } catch let error as HiveAxylError {
            guard case .invalidArgument = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
        }
    }

    private func pushTarget() -> Hiveng_V1_PushTarget {
        var target = Hiveng_V1_PushTarget()
        target.id = "target-1"
        target.projectID = TestSupport.projectId
        target.playerID = "player-1"
        target.fid = "fid-1"
        target.tokenPreview = "abcd...1234"
        target.platform = "ios"
        target.appIdentifier = "com.hiveaxyl.sample"
        target.language = "ko"
        target.enabled = true
        return target
    }
}
