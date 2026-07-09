import Foundation

public final class NoticeAPI: @unchecked Sendable {
    private let lock = NSLock()
    private var client: ConnectClient?
    private var language = ""

    func bind(client: ConnectClient, language: String) {
        lock.lock()
        self.client = client
        self.language = language
        lock.unlock()
    }

    func unbind() {
        lock.lock()
        client = nil
        language = ""
        lock.unlock()
    }

    public func listActiveNotices() async throws -> [Notice] {
        let activeClient = try requireClient()
        let selectedLanguage = currentLanguage()
        let request = Hiveng_V1_ListActiveNoticesRequest()
        let response: Hiveng_V1_ListActiveNoticesResponse = try await activeClient.unary(
            "NoticeService", "ListActiveNotices", request
        )
        return response.notices.map { Notice(message: $0, language: selectedLanguage) }
    }

    private func requireClient() throws -> ConnectClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client else {
            throw HiveAxylError.transport("discovery returned no endpoint for domain: notice")
        }
        return client
    }

    private func currentLanguage() -> String {
        lock.lock()
        defer { lock.unlock() }
        return language
    }
}
