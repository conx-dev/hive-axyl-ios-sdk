import Foundation

public struct ListMailResult: Equatable {
    public let mail: [Mail]
    public let nextPageToken: String
    public let total: Int64
}

public struct CheckNewMailResult: Equatable {
    public let hasNewMail: Bool
}

public final class MailboxAPI: @unchecked Sendable {
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

    public func listMail(
        pageSize: Int32 = 20,
        pageToken: String = "",
        includeClaimed: Bool = false
    ) async throws -> ListMailResult {
        let activeClient = try requireClient()
        let selectedLanguage = currentLanguage()
        var request = Hiveng_V1_ListMailRequest()
        request.page.pageSize = pageSize
        request.page.pageToken = pageToken
        request.includeClaimed = includeClaimed
        let response: Hiveng_V1_ListMailResponse = try await activeClient.unary(
            "MailboxService", "ListMail", request
        )
        return ListMailResult(
            mail: response.mail.map { Mail(message: $0, language: selectedLanguage) },
            nextPageToken: response.page.nextPageToken,
            total: response.page.total
        )
    }

    public func checkNewMail() async throws -> CheckNewMailResult {
        let activeClient = try requireClient()
        let request = Hiveng_V1_CheckNewMailRequest()
        let response: Hiveng_V1_CheckNewMailResponse = try await activeClient.unary(
            "MailboxService", "CheckNewMail", request
        )
        return CheckNewMailResult(
            hasNewMail: response.hasNewMail_p
        )
    }

    public func claimMail(mailID: String) async throws -> Mail {
        let activeClient = try requireClient()
        let selectedLanguage = currentLanguage()
        var request = Hiveng_V1_ClaimMailRequest()
        request.mailID = mailID
        let response: Hiveng_V1_ClaimMailResponse = try await activeClient.unary(
            "MailboxService", "ClaimMail", request
        )
        guard response.hasMail else {
            throw HiveAxylError.transport("claim response missing mail")
        }
        return Mail(message: response.mail, language: selectedLanguage)
    }

    private func requireClient() throws -> ConnectClient {
        lock.lock()
        defer { lock.unlock() }
        guard let client else {
            throw HiveAxylError.transport("discovery returned no endpoint for domain: mailbox")
        }
        return client
    }

    private func currentLanguage() -> String {
        lock.lock()
        defer { lock.unlock() }
        return language
    }
}
