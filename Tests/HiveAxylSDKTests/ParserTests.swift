import Foundation
import SwiftProtobuf
import XCTest
@testable import HiveAxylSDK

final class ParserTests: XCTestCase {
    private func envelope(code: String, message: String, detailValue: String) throws -> Data {
        let object: [String: Any] = [
            "code": code,
            "message": message,
            "details": [["type": "hiveng.v1.ErrorDetail", "value": detailValue]],
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testParseBannedDetailWithUnpaddedBase64() throws {
        var detail = Hiveng_V1_ErrorDetail()
        detail.code = .playerBanned
        detail.metadata = ["reason": "abuse", "permanent": "true"]
        let raw = Data(try detail.serializedBytes() as [UInt8])
        let unpadded = raw.base64EncodedString().replacingOccurrences(of: "=", with: "")
        let body = try envelope(code: "permission_denied", message: "banned", detailValue: unpadded)

        let error = ConnectErrorParser.parse(statusCode: 403, body: body)

        guard case let .banned(reason, until, permanent) = error else {
            return XCTFail("expected banned, got \(error)")
        }
        XCTAssertEqual(reason, "abuse")
        XCTAssertTrue(permanent)
        XCTAssertNil(until)
    }

    func testParseUrlSafeBase64Detail() throws {
        var detail = Hiveng_V1_ErrorDetail()
        detail.code = .geoBlocked
        detail.metadata = ["country": "RU"]
        let raw = Data(try detail.serializedBytes() as [UInt8])
        let urlSafe = raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        let body = try envelope(code: "failed_precondition", message: "geo", detailValue: urlSafe)

        let error = ConnectErrorParser.parse(statusCode: 451, body: body)

        guard case let .geoBlocked(country) = error else {
            return XCTFail("expected geoBlocked, got \(error)")
        }
        XCTAssertEqual(country, "RU")
    }

    func testParseRetryableConnectCodeWithoutDetailMapsToTransport() throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["code": "unavailable", "message": "down"]
        )
        let error = ConnectErrorParser.parse(statusCode: 503, body: body)

        guard case let .transport(message) = error else {
            return XCTFail("expected transport, got \(error)")
        }
        XCTAssertEqual(message, "down")
    }

    func testParseNonJsonBodyMapsToTransport() {
        let error = ConnectErrorParser.parse(statusCode: 500, body: Data("not json".utf8))

        guard case .transport = error else {
            return XCTFail("expected transport, got \(error)")
        }
    }

    func testDecodeBase64HandlesPaddingVariants() {
        let original = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let padded = original.base64EncodedString()
        let unpadded = padded.replacingOccurrences(of: "=", with: "")

        XCTAssertEqual(ConnectErrorParser.decodeBase64(padded), original)
        XCTAssertEqual(ConnectErrorParser.decodeBase64(unpadded), original)
    }

    func testResolveLocalizedPrefersExactThenBaseThenEnglish() {
        let map = ["en": "E", "ko": "K", "pt-BR": "PB"]
        XCTAssertEqual(resolveLocalized(map, language: "ko"), "K")
        XCTAssertEqual(resolveLocalized(map, language: "pt-BR"), "PB")
        XCTAssertEqual(resolveLocalized(map, language: "ko-KR"), "K")
        XCTAssertEqual(resolveLocalized(map, language: "de"), "E")
    }

    func testRfc3339RoundTrip() {
        let raw = "2026-06-15T12:34:56Z"
        let date = RFC3339.parse(raw)
        XCTAssertNotNil(date)
        XCTAssertEqual(RFC3339.format(date!), raw)
        XCTAssertNotNil(RFC3339.parse("2026-06-15T12:34:56.789Z"))
    }
}
