import Foundation

struct StubResponse {
    let statusCode: Int
    let body: Data
    let headers: [String: String]

    init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }
}

struct CapturedRequest {
    let path: String
    let body: Data
    let authorization: String?
    let playerToken: String?
    let contentType: String?
}

// 큐 기반 스텁: 핸들러가 들어온 요청을 받아 다음 응답을 결정한다.
final class MockRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((CapturedRequest) throws -> StubResponse)?
    private(set) var captured: [CapturedRequest] = []

    func onRequest(_ handler: @escaping (CapturedRequest) throws -> StubResponse) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func resolve(_ request: CapturedRequest) throws -> StubResponse {
        lock.lock()
        captured.append(request)
        let current = handler
        lock.unlock()
        guard let current else {
            throw NSError(domain: "MockRouter", code: -1)
        }
        return try current(request)
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return captured.count
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var router = MockRouter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = MockURLProtocol.bodyData(from: request)
        let captured = CapturedRequest(
            path: request.url?.path ?? "",
            body: body,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            playerToken: request.value(forHTTPHeaderField: "X-Player-Token"),
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        )
        do {
            let stub = try MockURLProtocol.router.resolve(captured)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // URLProtocol은 httpBody를 비우고 httpBodyStream으로 전달하는 경우가 있어 둘 다 처리
    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
