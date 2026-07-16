import Foundation

public let HiveAxylDefaultGatewayUrl = "https://gw-test-gcl.c2xstation.net:8081"

public struct HiveAxylConfig {
    // 디스커버리 게이트웨이 베이스 URL (예: "https://gateway.hive-axyl.io")
    public var gatewayUrl: String
    public var projectId: String
    public var apiKey: String
    public var clientVersion: String
    public var language: String
    public var debug: Bool
    // 테스트 주입용 훅 — 운영 코드는 기본값 사용
    public var tokenStorage: TokenStorage?
    public var urlSessionConfiguration: URLSessionConfiguration?
    var guestInstallationStorage: GuestInstallationStorage?

    public init(
        gatewayUrl: String = HiveAxylDefaultGatewayUrl,
        projectId: String,
        apiKey: String,
        clientVersion: String = "",
        language: String = Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
        debug: Bool = false,
        tokenStorage: TokenStorage? = nil,
        urlSessionConfiguration: URLSessionConfiguration? = nil
    ) {
        self.gatewayUrl = gatewayUrl
        self.projectId = projectId
        self.apiKey = apiKey
        self.clientVersion = clientVersion
        self.language = language
        self.debug = debug
        self.tokenStorage = tokenStorage
        self.urlSessionConfiguration = urlSessionConfiguration
        self.guestInstallationStorage = nil
    }
}

struct ResolvedConfig {
    let gatewayUrl: String
    let projectId: String
    let apiKey: String
    let clientVersion: String
    let language: String
    let debug: Bool

    init(_ config: HiveAxylConfig) throws {
        var trimmed = config.gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed = String(trimmed.dropLast())
        }
        if trimmed.isEmpty {
            trimmed = HiveAxylDefaultGatewayUrl
        }
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            throw HiveAxylError.invalidArgument("invalid gatewayUrl: \(config.gatewayUrl)")
        }
        guard !config.apiKey.isEmpty else {
            throw HiveAxylError.invalidArgument("apiKey is required")
        }
        let trimmedProjectId = config.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectId.isEmpty else {
            throw HiveAxylError.invalidArgument("projectId is required")
        }
        gatewayUrl = trimmed
        projectId = trimmedProjectId
        apiKey = config.apiKey
        clientVersion = config.clientVersion
        language = config.language
        debug = config.debug
    }
}
