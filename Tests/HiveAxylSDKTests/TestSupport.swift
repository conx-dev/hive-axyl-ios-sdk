import Foundation
import SwiftProtobuf
import XCTest
@testable import HiveAxylSDK

enum TestSupport {
    static let authBaseUrl = "https://auth.test.hive-axyl"
    static let remotePushBaseUrl = "https://remote-push.test.hive-axyl"
    static let projectId = "a4497665-e2ab-4628-aa65-e7ef5a9ab423"

    static func makeConfiguration(_ router: MockRouter) -> URLSessionConfiguration {
        MockURLProtocol.router = router
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    static func makeConfig(
        router: MockRouter,
        storage: TokenStorage,
        guestStorage: GuestInstallationStorage = TestGuestInstallationStorage()
    ) -> HiveAxylConfig {
        var config = HiveAxylConfig(
            gatewayUrl: "https://gateway.test.hive-axyl",
            projectId: projectId,
            apiKey: "test-api-key",
            clientVersion: "1.0.0",
            debug: false,
            tokenStorage: storage,
            urlSessionConfiguration: makeConfiguration(router)
        )
        config.guestInstallationStorage = guestStorage
        return config
    }

    // ResolveEndpoints를 자동 응답한 뒤 나머지는 handler에 위임한다.
    static func routeWithDiscovery(
        _ router: MockRouter,
        _ handler: @escaping (CapturedRequest) throws -> StubResponse
    ) {
        router.onRequest { request in
            if request.path == "/hiveng.v1.DiscoveryService/ResolveEndpoints" {
                let decoded = try Hiveng_V1_ResolveEndpointsRequest(serializedBytes: request.body)
                XCTAssertEqual(decoded.projectID, projectId)
                XCTAssertEqual(request.authorization, "Bearer test-api-key")
                var response = Hiveng_V1_ResolveEndpointsResponse()
                var entry = Hiveng_V1_EndpointEntry()
                entry.domain = "auth"
                entry.baseURL = authBaseUrl
                var pushEntry = Hiveng_V1_EndpointEntry()
                pushEntry.domain = "remote_push"
                pushEntry.baseURL = remotePushBaseUrl
                response.endpoints = [entry, pushEntry]
                response.ttlSeconds = 300
                return StubResponse(statusCode: 200, body: try proto(response))
            }
            return try handler(request)
        }
    }

    // discovery까지 끝나 초기화된 HiveAxyl. router는 호출 전에 핸들러가 설정돼 있어야 한다.
    static func makeInitializedHive(
        router: MockRouter,
        storage: TokenStorage,
        guestStorage: GuestInstallationStorage = TestGuestInstallationStorage()
    ) async throws -> HiveAxyl {
        let config = makeConfig(router: router, storage: storage, guestStorage: guestStorage)
        let hive = try HiveAxyl(config: config)
        try await hive.initialize()
        return hive
    }

    // ConnectRPC JSON 에러 봉투 + base64(ErrorDetail) detail
    static func errorBody(
        code: Hiveng_V1_ErrorCode,
        message: String,
        metadata: [String: String] = [:],
        connectCode: String = "failed_precondition"
    ) throws -> Data {
        var detail = Hiveng_V1_ErrorDetail()
        detail.code = code
        detail.metadata = metadata
        let raw = try detail.serializedBytes() as [UInt8]
        let base64 = Data(raw).base64EncodedString()
        let envelope: [String: Any] = [
            "code": connectCode,
            "message": message,
            "details": [
                ["type": "hiveng.v1.ErrorDetail", "value": base64],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    static func proto<M: Message>(_ message: M) throws -> Data {
        Data(try message.serializedBytes() as [UInt8])
    }

    static func tokenPair(access: String, refresh: String) -> Hiveng_V1_TokenPair {
        var pair = Hiveng_V1_TokenPair()
        pair.accessToken = access
        pair.refreshToken = refresh
        return pair
    }

    static func player(id: String, country: String = "KR") -> Hiveng_V1_Player {
        var player = Hiveng_V1_Player()
        player.playerID = id
        player.projectID = "proj-1"
        player.country = country
        player.email = "player@test.dev"
        player.nickname = "Tester"
        player.lastLoginPlatform = .ios
        player.providers = [.google]
        return player
    }
}

final class TestGuestInstallationStorage: GuestInstallationStorage {
    private let canWrite: Bool
    private(set) var value: String?

    init(value: String? = nil, canWrite: Bool = true) {
        self.value = value
        self.canWrite = canWrite
    }

    func get() throws -> String? {
        value
    }

    func set(_ value: String) throws -> Bool {
        if !canWrite {
            return false
        }
        self.value = value
        return true
    }
}
