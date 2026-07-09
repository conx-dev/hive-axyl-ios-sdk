import Foundation
import SwiftProtobuf

final class ConnectClient: @unchecked Sendable {
    private let baseUrl: String
    private let apiKey: String?
    private let language: String
    private let session: Session
    private let urlSession: URLSession
    private let debug: Bool

    var onBannedError: ((HiveAxylError) -> Void)?

    init(baseUrl: String, apiKey: String?, language: String, session: Session,
         urlSession: URLSession, debug: Bool) {
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.language = language
        self.session = session
        self.urlSession = urlSession
        self.debug = debug
    }

    func unary<Req: Message, Res: Message>(
        _ service: String,
        _ method: String,
        _ request: Req,
        allowsSessionRefresh: Bool = true,
        includesPlayerToken: Bool = true
    ) async throws -> Res {
        do {
            return try await sendOnce(service, method, request, includesPlayerToken: includesPlayerToken)
        } catch let error as HiveAxylError {
            guard allowsSessionRefresh, isSessionExpired(error) else {
                throw error
            }
            // SESSION_EXPIRED → 토큰 회전 후 원 요청 1회만 재시도
            let refreshed = await session.tryRefresh()
            guard refreshed else {
                if let refreshError = session.consumeRefreshError() {
                    throw refreshError
                }
                throw error
            }
            return try await sendOnce(service, method, request, includesPlayerToken: includesPlayerToken)
        }
    }

    private func isSessionExpired(_ error: HiveAxylError) -> Bool {
        guard case .code(.sessionExpired, _) = error else {
            return false
        }
        return true
    }

    private func sendOnce<Req: Message, Res: Message>(
        _ service: String,
        _ method: String,
        _ message: Req,
        includesPlayerToken: Bool
    ) async throws -> Res {
        let urlRequest = try buildRequest(service, method, message, includesPlayerToken: includesPlayerToken)
        let (data, response) = try await perform(urlRequest)
        guard response.statusCode == 200 else {
            let error = ConnectErrorParser.parse(statusCode: response.statusCode, body: data)
            log("\(service)/\(method) failed: \(error)")
            if case .banned = error {
                onBannedError?(error)
            }
            throw error
        }
        do {
            return try Res(serializedBytes: data)
        } catch {
            throw HiveAxylError.transport("invalid response body for \(service)/\(method)")
        }
    }

    private func buildRequest<Req: Message>(
        _ service: String,
        _ method: String,
        _ message: Req,
        includesPlayerToken: Bool
    ) throws -> URLRequest {
        let raw = "\(baseUrl)/hiveng.v1.\(service)/\(method)"
        guard let url = URL(string: raw) else {
            throw HiveAxylError.invalidArgument("invalid url: \(raw)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/proto", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if !language.isEmpty {
                request.setValue(language, forHTTPHeaderField: "X-Hive-Ng-Language")
            }
            if includesPlayerToken, let token = session.accessToken, method != "RefreshToken" {
                request.setValue(token, forHTTPHeaderField: "X-Player-Token")
            }
        }
        let body: Data = try message.serializedBytes()
        request.httpBody = body
        return request
    }

    // iOS 14 지원을 위해 async URLSession API 대신 continuation 사용
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: HiveAxylError.transport(error.localizedDescription))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: HiveAxylError.transport("non-HTTP response"))
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }

    private func log(_ message: @autoclosure () -> String) {
        guard debug else { return }
        print("[hive-axyl] \(message())")
    }
}
