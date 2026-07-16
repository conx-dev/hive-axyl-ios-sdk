import Foundation

// SDK 공개 진입점. init으로 구성 후 initialize()에서 게이트웨이 디스커버리를 수행한다.
public final class HiveAxyl: @unchecked Sendable {
    public let auth: AuthAPI
    public let notice: NoticeAPI
    public let mailbox: MailboxAPI
    public let payment: PaymentAPI
    public let push: PushAPI

    private let config: ResolvedConfig
    private let session: Session
    private let urlSession: URLSession
    private let lock = NSLock()
    private var ready = false

    public init(config: HiveAxylConfig) throws {
        self.config = try ResolvedConfig(config)
        let storage = config.tokenStorage ?? KeychainTokenStorage()
        self.session = Session(storage: storage)
        self.urlSession = URLSession(configuration: config.urlSessionConfiguration ?? .default)
        let guestStorage = config.guestInstallationStorage ?? KeychainGuestInstallationStorage()
        let guestInstallation = GuestInstallation(storage: guestStorage)
        self.auth = AuthAPI(session: session, guestInstallation: guestInstallation)
        self.notice = NoticeAPI()
        self.mailbox = MailboxAPI()
        self.payment = PaymentAPI()
        self.push = PushAPI()
        session.onCleared = { [weak auth] in auth?.clearPlayer() }
    }

    // 게이트웨이 디스커버리로 도메인별 베이스 URL을 받아 도메인 클라이언트를 구성한다.
    public func initialize() async throws {
        let gateway = ConnectClient(
            baseUrl: config.gatewayUrl, apiKey: config.apiKey, language: config.language,
            session: session, urlSession: urlSession, debug: config.debug
        )
        let resolved = try await Discovery.resolve(
            client: gateway,
            clientVersion: config.clientVersion,
            projectId: config.projectId
        )
        guard let authBaseUrl = resolved["auth"], !authBaseUrl.isEmpty else {
            throw HiveAxylError.transport("discovery returned no endpoint for domain: auth")
        }

        let authClient = ConnectClient(
            baseUrl: authBaseUrl, apiKey: config.apiKey, language: config.language,
            session: session, urlSession: urlSession, debug: config.debug
        )
        // refresh 자신의 만료에 재귀 진입하지 않도록 refresh 경로는 재시도 비활성화
        session.refreshFn = { [weak authClient] refreshToken in
            guard let authClient else {
                throw HiveAxylError.notInitialized
            }
            var request = Hiveng_V1_RefreshTokenRequest()
            request.refreshToken = refreshToken
            let response: Hiveng_V1_RefreshTokenResponse = try await authClient.unary(
                "AuthService", "RefreshToken", request, allowsSessionRefresh: false
            )
            guard response.hasTokenPair else {
                throw HiveAxylError.transport("refresh response missing token pair")
            }
            return response.tokenPair
        }
        authClient.onBannedError = { [weak auth] error in auth?.emitIfBanned(error) }
        auth.bind(client: authClient)
        if let noticeBaseUrl = resolved["notice"], !noticeBaseUrl.isEmpty {
            let noticeClient = ConnectClient(
                baseUrl: noticeBaseUrl, apiKey: config.apiKey, language: config.language,
                session: session, urlSession: urlSession, debug: config.debug
            )
            notice.bind(client: noticeClient, language: config.language)
        } else {
            notice.unbind()
        }
        if let mailboxBaseUrl = resolved["mailbox"], !mailboxBaseUrl.isEmpty {
            let mailboxClient = ConnectClient(
                baseUrl: mailboxBaseUrl, apiKey: config.apiKey, language: config.language,
                session: session, urlSession: urlSession, debug: config.debug
            )
            mailbox.bind(client: mailboxClient, language: config.language)
        } else {
            mailbox.unbind()
        }
        if let paymentBaseUrl = resolved["payment"], !paymentBaseUrl.isEmpty {
            let paymentClient = ConnectClient(
                baseUrl: paymentBaseUrl, apiKey: config.apiKey, language: config.language,
                session: session, urlSession: urlSession, debug: config.debug
            )
            payment.bind(client: paymentClient)
        } else {
            payment.unbind()
        }
        if let remotePushBaseUrl = resolved["remote_push"], !remotePushBaseUrl.isEmpty {
            let remotePushClient = ConnectClient(
                baseUrl: remotePushBaseUrl, apiKey: config.apiKey, language: config.language,
                session: session, urlSession: urlSession, debug: config.debug
            )
            push.bind(client: remotePushClient)
        } else {
            push.unbind()
        }

        lock.lock()
        ready = true
        lock.unlock()
    }

    public var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready
    }
}
