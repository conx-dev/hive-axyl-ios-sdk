import Foundation

public typealias BannedCallback = (_ reason: String, _ until: Date?, _ permanent: Bool) -> Void

public final class AuthAPI: @unchecked Sendable {
    private let session: Session
    private let lock = NSLock()
    private var player: Player?
    private var client: ConnectClient?
    private var bannedCallbacks: [BannedCallback] = []

    init(session: Session) {
        self.session = session
    }

    func bind(client: ConnectClient) {
        lock.lock()
        self.client = client
        lock.unlock()
    }

    public func getLoginProviders(countryOverride: String = "") async throws -> LoginProviders {
        let client = try requireClient()
        var request = Hiveng_V1_GetLoginProvidersRequest()
        request.countryOverride = countryOverride
        request.platform = .ios
        let response: Hiveng_V1_GetLoginProvidersResponse = try await client.unary(
            "AuthService", "GetLoginProviders", request,
            allowsSessionRefresh: false,
            includesPlayerToken: false
        )
        return LoginProviders(message: response)
    }

    // 클라이언트가 Google Sign-In으로 획득한 idToken으로 로그인한다.
    public func loginWithGoogle(idToken: String) async throws -> Player {
        guard !idToken.isEmpty else {
            throw HiveAxylError.invalidArgument("idToken is required")
        }
        return try await login(provider: .google, providerToken: idToken)
    }

    public func loginWithApple(identityToken: String) async throws -> Player {
        guard !identityToken.isEmpty else {
            throw HiveAxylError.invalidArgument("identityToken is required")
        }
        return try await login(provider: .apple, providerToken: identityToken)
    }

    public func loginWithFacebook(accessToken: String) async throws -> Player {
        guard !accessToken.isEmpty else {
            throw HiveAxylError.invalidArgument("accessToken is required")
        }
        return try await login(provider: .facebook, providerToken: accessToken)
    }

    // 외부 IdP 없이 디바이스 식별자로 게스트 계정에 로그인한다.
    public func loginAsGuest(deviceId: String) async throws -> Player {
        guard !deviceId.isEmpty else {
            throw HiveAxylError.invalidArgument("deviceId is required")
        }
        return try await login(provider: .guest, providerToken: deviceId)
    }

    // 저장된 토큰으로 세션을 복원한다. 토큰이 없거나 만료·무효면 nil.
    public func restoreSession() async -> Player? {
        guard session.accessToken != nil else {
            return nil
        }
        let client: ConnectClient
        do {
            client = try requireClient()
        } catch {
            return nil
        }
        do {
            return try await fetchPlayer(client)
        } catch {
            return nil
        }
    }

    public func getPlayer() async throws -> Player? {
        guard session.accessToken != nil else {
            return nil
        }
        let client = try requireClient()
        return try await fetchPlayer(client)
    }

    public func logout() async throws {
        let client = try requireClient()
        if session.accessToken != nil {
            do {
                let _: Hiveng_V1_LogoutResponse = try await client.unary(
                    "AuthService", "Logout", Hiveng_V1_LogoutRequest()
                )
            } catch {
                // 서버 로그아웃 실패와 무관하게 로컬 세션 정리는 보장
            }
        }
        session.clear()
        clearPlayer()
    }

    public func currentPlayer() -> Player? {
        lock.lock()
        defer { lock.unlock() }
        return player
    }

    public func playerValidationToken() -> String? {
        session.playerValidationToken
    }

    public func onBanned(_ callback: @escaping BannedCallback) {
        lock.lock()
        bannedCallbacks.append(callback)
        lock.unlock()
    }

    private func login(provider: Hiveng_V1_IdentityProvider, providerToken: String) async throws -> Player {
        let client = try requireClient()
        var request = Hiveng_V1_LoginWithProviderRequest()
        request.provider = provider
        request.providerToken = providerToken
        request.platform = .ios
        let response: Hiveng_V1_LoginWithProviderResponse = try await client.unary(
            "AuthService", "LoginWithProvider", request,
            allowsSessionRefresh: false,
            includesPlayerToken: false
        )
        guard response.hasPlayer, response.hasTokenPair else {
            throw HiveAxylError.transport("login response missing player or token pair")
        }
        session.save(response.tokenPair)
        let logged = Player(message: response.player)
        setPlayer(logged)
        return logged
    }

    private func fetchPlayer(_ client: ConnectClient) async throws -> Player? {
        let response: Hiveng_V1_GetPlayerResponse = try await client.unary(
            "AuthService", "GetPlayer", Hiveng_V1_GetPlayerRequest()
        )
        guard response.hasPlayer else {
            return nil
        }
        let restored = Player(message: response.player)
        setPlayer(restored)
        return restored
    }

    func emitIfBanned(_ error: HiveAxylError) {
        guard case let .banned(reason, until, permanent) = error else {
            return
        }
        lock.lock()
        let callbacks = bannedCallbacks
        lock.unlock()
        for callback in callbacks {
            callback(reason, until, permanent)
        }
    }

    func clearPlayer() {
        lock.lock()
        player = nil
        lock.unlock()
    }

    private func setPlayer(_ value: Player) {
        lock.lock()
        player = value
        lock.unlock()
    }

    private func requireClient() throws -> ConnectClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client else {
            throw HiveAxylError.notInitialized
        }
        return client
    }
}
