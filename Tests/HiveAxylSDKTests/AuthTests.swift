import Foundation
import SwiftProtobuf
import XCTest
@testable import HiveAxylSDK

final class AuthTests: XCTestCase {
    func testInitializeResolvesAuthEndpoint() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { _ in
            StubResponse(statusCode: 200, body: Data())
        }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        XCTAssertTrue(hive.isReady)
    }

    func testInitializeFailsWhenAuthEndpointMissing() async throws {
        let router = MockRouter()
        router.onRequest { _ in
            var response = Hiveng_V1_ResolveEndpointsResponse()
            response.ttlSeconds = 300
            return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
        }
        let hive = try HiveAxyl(config: TestSupport.makeConfig(router: router, storage: InMemoryTokenStorage()))

        do {
            try await hive.initialize()
            XCTFail("expected transport error")
        } catch let error as HiveAxylError {
            guard case let .transport(message) = error else {
                return XCTFail("expected transport, got \(error)")
            }
            XCTAssertTrue(message.contains("auth"))
        }
    }

    func testGetLoginProvidersReturnsProviderNamesAndCountry() async throws {
        let router = MockRouter()
        var response = Hiveng_V1_GetLoginProvidersResponse()
        response.providers = [.google, .guest]
        response.country = "KR"
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/GetLoginProviders")
            XCTAssertNil(request.playerToken)
            let decoded = try Hiveng_V1_GetLoginProvidersRequest(serializedBytes: request.body)
            XCTAssertEqual(decoded.countryOverride, "")
            XCTAssertEqual(decoded.platform, .ios)
            return StubResponse(statusCode: 200, body: try TestSupport.proto(response))
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-stale")
        storage.set(Session.Keys.refreshToken, "refresh-stale")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let result = try await hive.auth.getLoginProviders()

        XCTAssertEqual(result.country, "KR")
        XCTAssertEqual(result.providers, ["google", "guest"])
    }

    func testLoginWithGoogleSendsIdTokenAndPersists() async throws {
        let router = MockRouter()
        var loginResponse = Hiveng_V1_LoginWithProviderResponse()
        loginResponse.player = TestSupport.player(id: "player-g-1")
        loginResponse.tokenPair = TestSupport.tokenPair(access: "access-1", refresh: "refresh-1")
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/LoginWithProvider")
            XCTAssertNil(request.playerToken)
            let decoded = try Hiveng_V1_LoginWithProviderRequest(serializedBytes: request.body)
            XCTAssertEqual(decoded.provider, .google)
            XCTAssertEqual(decoded.providerToken, "google-id-token")
            XCTAssertEqual(decoded.platform, .ios)
            return StubResponse(statusCode: 200, body: try TestSupport.proto(loginResponse))
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-stale")
        storage.set(Session.Keys.refreshToken, "refresh-stale")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let player = try await hive.auth.loginWithGoogle(idToken: "google-id-token")

        XCTAssertEqual(player.playerId, "player-g-1")
        XCTAssertEqual(player.email, "player@test.dev")
        XCTAssertEqual(player.nickname, "Tester")
        XCTAssertEqual(player.lastLoginPlatform, "ios")
        XCTAssertEqual(player.providers, ["google"])
        XCTAssertEqual(hive.auth.currentPlayer()?.playerId, "player-g-1")
        XCTAssertEqual(storage.get(Session.Keys.accessToken), "access-1")
        XCTAssertEqual(storage.get(Session.Keys.refreshToken), "refresh-1")
    }

    func testLoginWithAppleSendsIdentityTokenAndPersists() async throws {
        let router = MockRouter()
        var loginResponse = Hiveng_V1_LoginWithProviderResponse()
        loginResponse.player = TestSupport.player(id: "player-a-1")
        loginResponse.tokenPair = TestSupport.tokenPair(access: "access-a", refresh: "refresh-a")
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/LoginWithProvider")
            XCTAssertNil(request.playerToken)
            let decoded = try Hiveng_V1_LoginWithProviderRequest(serializedBytes: request.body)
            XCTAssertEqual(decoded.provider, .apple)
            XCTAssertEqual(decoded.providerToken, "apple-identity-token")
            XCTAssertEqual(decoded.platform, .ios)
            return StubResponse(statusCode: 200, body: try TestSupport.proto(loginResponse))
        }
        let storage = InMemoryTokenStorage()
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let player = try await hive.auth.loginWithApple(identityToken: "apple-identity-token")

        XCTAssertEqual(player.playerId, "player-a-1")
        XCTAssertEqual(hive.auth.currentPlayer()?.playerId, "player-a-1")
        XCTAssertEqual(storage.get(Session.Keys.accessToken), "access-a")
        XCTAssertEqual(storage.get(Session.Keys.refreshToken), "refresh-a")
    }

    func testLoginWithFacebookSendsAccessTokenAndPersists() async throws {
        let router = MockRouter()
        var loginResponse = Hiveng_V1_LoginWithProviderResponse()
        loginResponse.player = TestSupport.player(id: "player-f-1")
        loginResponse.tokenPair = TestSupport.tokenPair(access: "access-f", refresh: "refresh-f")
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/LoginWithProvider")
            XCTAssertNil(request.playerToken)
            let decoded = try Hiveng_V1_LoginWithProviderRequest(serializedBytes: request.body)
            XCTAssertEqual(decoded.provider, .facebook)
            XCTAssertEqual(decoded.providerToken, "facebook-access-token")
            XCTAssertEqual(decoded.platform, .ios)
            return StubResponse(statusCode: 200, body: try TestSupport.proto(loginResponse))
        }
        let storage = InMemoryTokenStorage()
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let player = try await hive.auth.loginWithFacebook(accessToken: "facebook-access-token")

        XCTAssertEqual(player.playerId, "player-f-1")
        XCTAssertEqual(hive.auth.currentPlayer()?.playerId, "player-f-1")
        XCTAssertEqual(storage.get(Session.Keys.accessToken), "access-f")
        XCTAssertEqual(storage.get(Session.Keys.refreshToken), "refresh-f")
    }

    func testLoginAsGuestSendsDeviceIdAndPersists() async throws {
        let router = MockRouter()
        var loginResponse = Hiveng_V1_LoginWithProviderResponse()
        loginResponse.player = TestSupport.player(id: "player-guest-1")
        loginResponse.tokenPair = TestSupport.tokenPair(access: "access-g", refresh: "refresh-g")
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/LoginWithProvider")
            let decoded = try Hiveng_V1_LoginWithProviderRequest(serializedBytes: request.body)
            XCTAssertEqual(decoded.provider, .guest)
            XCTAssertEqual(decoded.providerToken, "device-abc")
            XCTAssertEqual(decoded.platform, .ios)
            return StubResponse(statusCode: 200, body: try TestSupport.proto(loginResponse))
        }
        let storage = InMemoryTokenStorage()
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let player = try await hive.auth.loginAsGuest(deviceId: "device-abc")

        XCTAssertEqual(player.playerId, "player-guest-1")
        XCTAssertEqual(hive.auth.currentPlayer()?.playerId, "player-guest-1")
        XCTAssertEqual(storage.get(Session.Keys.accessToken), "access-g")
        XCTAssertEqual(storage.get(Session.Keys.refreshToken), "refresh-g")
    }

    func testEmptyDeviceIdThrowsInvalidArgument() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { _ in StubResponse(statusCode: 200, body: Data()) }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        do {
            _ = try await hive.auth.loginAsGuest(deviceId: "")
            XCTFail("expected invalidArgument")
        } catch let error as HiveAxylError {
            guard case .invalidArgument = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
        }
    }

    func testEmptyIdTokenThrowsInvalidArgument() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { _ in StubResponse(statusCode: 200, body: Data()) }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        do {
            _ = try await hive.auth.loginWithGoogle(idToken: "")
            XCTFail("expected invalidArgument")
        } catch let error as HiveAxylError {
            guard case .invalidArgument = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
        }
    }

    func testEmptyAppleIdentityTokenThrowsInvalidArgument() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { _ in StubResponse(statusCode: 200, body: Data()) }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        do {
            _ = try await hive.auth.loginWithApple(identityToken: "")
            XCTFail("expected invalidArgument")
        } catch let error as HiveAxylError {
            guard case .invalidArgument = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
        }
    }

    func testEmptyFacebookAccessTokenThrowsInvalidArgument() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { _ in StubResponse(statusCode: 200, body: Data()) }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        do {
            _ = try await hive.auth.loginWithFacebook(accessToken: "")
            XCTFail("expected invalidArgument")
        } catch let error as HiveAxylError {
            guard case .invalidArgument = error else {
                return XCTFail("expected invalidArgument, got \(error)")
            }
        }
    }

    func testBannedErrorExtractedAndEmitted() async throws {
        let router = MockRouter()
        let until = "2026-12-31T23:59:59Z"
        TestSupport.routeWithDiscovery(router) { _ in
            let body = try TestSupport.errorBody(
                code: .playerBanned,
                message: "account banned",
                metadata: ["reason": "cheating", "permanent": "false", "until": until]
            )
            return StubResponse(statusCode: 403, body: body)
        }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        var emittedReason: String?
        hive.auth.onBanned { reason, _, _ in emittedReason = reason }

        do {
            _ = try await hive.auth.loginWithGoogle(idToken: "google-id-token")
            XCTFail("expected banned error")
        } catch let error as HiveAxylError {
            guard case let .banned(reason, untilDate, permanent) = error else {
                return XCTFail("expected banned, got \(error)")
            }
            XCTAssertEqual(reason, "cheating")
            XCTAssertFalse(permanent)
            XCTAssertEqual(untilDate, RFC3339.parse(until))
            XCTAssertEqual(emittedReason, "cheating")
        }
    }

    func testGetPlayerSessionExpiredTriggersRefreshAndRetries() async throws {
        let router = MockRouter()
        var getPlayerResponse = Hiveng_V1_GetPlayerResponse()
        getPlayerResponse.player = TestSupport.player(id: "p")
        var refreshed = Hiveng_V1_RefreshTokenResponse()
        refreshed.tokenPair = TestSupport.tokenPair(access: "access-2", refresh: "refresh-2")

        let state = LockedCounter()
        TestSupport.routeWithDiscovery(router) { request in
            if request.path == "/hiveng.v1.AuthService/RefreshToken" {
                let decoded = try Hiveng_V1_RefreshTokenRequest(serializedBytes: request.body)
                XCTAssertEqual(decoded.refreshToken, "refresh-old")
                XCTAssertNil(request.playerToken)
                return StubResponse(statusCode: 200, body: try TestSupport.proto(refreshed))
            }
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/GetPlayer")
            // 첫 GetPlayer는 만료, 재시도는 토큰 회전 후 성공
            if state.next() == 0 {
                XCTAssertEqual(request.playerToken, "access-old")
                let body = try TestSupport.errorBody(
                    code: .sessionExpired, message: "expired", connectCode: "unauthenticated"
                )
                return StubResponse(statusCode: 401, body: body)
            }
            XCTAssertEqual(request.playerToken, "access-2")
            return StubResponse(statusCode: 200, body: try TestSupport.proto(getPlayerResponse))
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-old")
        storage.set(Session.Keys.refreshToken, "refresh-old")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let player = try await hive.auth.getPlayer()

        XCTAssertEqual(player?.playerId, "p")
        XCTAssertEqual(storage.get(Session.Keys.accessToken), "access-2")
        XCTAssertEqual(storage.get(Session.Keys.refreshToken), "refresh-2")
    }

    func testSessionExpiredRefreshBannedThrowsBannedAndClearsSession() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { request in
            if request.path == "/hiveng.v1.AuthService/RefreshToken" {
                let decoded = try Hiveng_V1_RefreshTokenRequest(serializedBytes: request.body)
                XCTAssertEqual(decoded.refreshToken, "refresh-old")
                XCTAssertNil(request.playerToken)
                let body = try TestSupport.errorBody(
                    code: .playerBanned,
                    message: "banned",
                    metadata: ["reason": "abuse", "permanent": "true"]
                )
                return StubResponse(statusCode: 403, body: body)
            }
            let body = try TestSupport.errorBody(
                code: .sessionExpired, message: "expired", connectCode: "unauthenticated"
            )
            return StubResponse(statusCode: 401, body: body)
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-old")
        storage.set(Session.Keys.refreshToken, "refresh-old")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        var emittedReason: String?
        hive.auth.onBanned { reason, _, _ in emittedReason = reason }

        do {
            _ = try await hive.auth.getPlayer()
            XCTFail("expected banned error")
        } catch let error as HiveAxylError {
            guard case let .banned(reason, _, permanent) = error else {
                return XCTFail("expected banned, got \(error)")
            }
            XCTAssertEqual(reason, "abuse")
            XCTAssertTrue(permanent)
            XCTAssertEqual(emittedReason, "abuse")
            XCTAssertNil(storage.get(Session.Keys.accessToken))
            XCTAssertNil(storage.get(Session.Keys.refreshToken))
        }
    }

    func testLogoutClearsLocalSessionEvenWhenServerFails() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { request in
            if request.path == "/hiveng.v1.AuthService/Logout" {
                return StubResponse(statusCode: 500, body: Data("boom".utf8))
            }
            return StubResponse(statusCode: 200, body: Data())
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-old")
        storage.set(Session.Keys.refreshToken, "refresh-old")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        try await hive.auth.logout()

        XCTAssertNil(storage.get(Session.Keys.accessToken))
        XCTAssertNil(storage.get(Session.Keys.refreshToken))
        XCTAssertNil(hive.auth.currentPlayer())
    }

    func testRestoreSessionReturnsNilWhenNoStoredToken() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { _ in
            XCTFail("저장된 토큰이 없으면 GetPlayer를 호출하지 않아야 한다")
            return StubResponse(statusCode: 200, body: Data())
        }
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: InMemoryTokenStorage())

        let restored = await hive.auth.restoreSession()

        XCTAssertNil(restored)
        XCTAssertNil(hive.auth.currentPlayer())
    }

    func testRestoreSessionRehydratesPlayerFromStoredToken() async throws {
        let router = MockRouter()
        var getPlayerResponse = Hiveng_V1_GetPlayerResponse()
        getPlayerResponse.player = TestSupport.player(id: "player-restored")
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/GetPlayer")
            XCTAssertEqual(request.playerToken, "access-stored")
            return StubResponse(statusCode: 200, body: try TestSupport.proto(getPlayerResponse))
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-stored")
        storage.set(Session.Keys.refreshToken, "refresh-stored")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let restored = await hive.auth.restoreSession()

        XCTAssertEqual(restored?.playerId, "player-restored")
        XCTAssertEqual(hive.auth.currentPlayer()?.playerId, "player-restored")
    }

    func testRestoreSessionRefreshesExpiredAccessToken() async throws {
        let router = MockRouter()
        var getPlayerResponse = Hiveng_V1_GetPlayerResponse()
        getPlayerResponse.player = TestSupport.player(id: "player-restored")
        var refreshed = Hiveng_V1_RefreshTokenResponse()
        refreshed.tokenPair = TestSupport.tokenPair(access: "access-new", refresh: "refresh-new")

        let state = LockedCounter()
        TestSupport.routeWithDiscovery(router) { request in
            if request.path == "/hiveng.v1.AuthService/RefreshToken" {
                let decoded = try Hiveng_V1_RefreshTokenRequest(serializedBytes: request.body)
                XCTAssertEqual(decoded.refreshToken, "refresh-old")
                XCTAssertNil(request.playerToken)
                return StubResponse(statusCode: 200, body: try TestSupport.proto(refreshed))
            }
            // 첫 GetPlayer는 만료, 토큰 회전 후 재시도는 성공
            if state.next() == 0 {
                let body = try TestSupport.errorBody(
                    code: .sessionExpired, message: "expired", connectCode: "unauthenticated"
                )
                return StubResponse(statusCode: 401, body: body)
            }
            return StubResponse(statusCode: 200, body: try TestSupport.proto(getPlayerResponse))
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-old")
        storage.set(Session.Keys.refreshToken, "refresh-old")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        let restored = await hive.auth.restoreSession()

        XCTAssertEqual(restored?.playerId, "player-restored")
        XCTAssertEqual(storage.get(Session.Keys.accessToken), "access-new")
        XCTAssertEqual(storage.get(Session.Keys.refreshToken), "refresh-new")
    }

    func testGetPlayerThrowsMaintenanceError() async throws {
        let router = MockRouter()
        TestSupport.routeWithDiscovery(router) { request in
            XCTAssertEqual(request.path, "/hiveng.v1.AuthService/GetPlayer")
            XCTAssertEqual(request.playerToken, "access-stored")
            let body = try TestSupport.errorBody(
                code: .maintenanceInProgress,
                message: "점검 시작",
                metadata: [
                    "message": "점검 시작",
                    "ends_at": "2026-06-23T00:36:00Z",
                ],
                connectCode: "unavailable"
            )
            return StubResponse(statusCode: 503, body: body)
        }
        let storage = InMemoryTokenStorage()
        storage.set(Session.Keys.accessToken, "access-stored")
        storage.set(Session.Keys.refreshToken, "refresh-stored")
        let hive = try await TestSupport.makeInitializedHive(router: router, storage: storage)

        do {
            _ = try await hive.auth.getPlayer()
            XCTFail("expected maintenance error")
        } catch let error as HiveAxylError {
            guard case let .maintenance(info) = error else {
                return XCTFail("expected maintenance, got \(error)")
            }
            XCTAssertEqual(info.message, "점검 시작")
        }
    }

    func testLoginBeforeInitializeThrowsNotInitialized() async throws {
        let router = MockRouter()
        let hive = try HiveAxyl(config: TestSupport.makeConfig(router: router, storage: InMemoryTokenStorage()))

        do {
            _ = try await hive.auth.loginWithGoogle(idToken: "google-id-token")
            XCTFail("expected notInitialized")
        } catch let error as HiveAxylError {
            XCTAssertEqual(error, .notInitialized)
        }
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value += 1
        return current
    }
}
