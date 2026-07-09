import Foundation

enum ConnectErrorParser {
    struct Envelope: Decodable {
        let code: String?
        let message: String?
        let details: [Detail]?

        struct Detail: Decodable {
            let type: String?
            let value: String?
        }
    }

    static func parse(statusCode: Int, body: Data) -> HiveAxylError {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else {
            return .transport("HTTP \(statusCode)")
        }
        let message = envelope.message ?? ""
        guard let detail = errorDetail(in: envelope) else {
            if isRetryableConnectCode(envelope.code) {
                return .transport(message.isEmpty ? "HTTP \(statusCode)" : message)
            }
            return .code(.unspecified, message: message)
        }
        return mapDetail(detail, message: message)
    }

    private static func isRetryableConnectCode(_ code: String?) -> Bool {
        code == "unavailable" || code == "deadline_exceeded"
    }

    private static func errorDetail(in envelope: Envelope) -> Hiveng_V1_ErrorDetail? {
        for candidate in envelope.details ?? [] {
            let rawType = candidate.type ?? ""
            let normalized = rawType.split(separator: "/").last.map(String.init) ?? rawType
            guard normalized == "hiveng.v1.ErrorDetail", let value = candidate.value else {
                continue
            }
            guard let bytes = decodeBase64(value) else {
                continue
            }
            if let detail = try? Hiveng_V1_ErrorDetail(serializedBytes: bytes) {
                return detail
            }
        }
        return nil
    }

    // 패딩 유무/URL-safe 변형 모두 허용
    static func decodeBase64(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: normalized)
    }

    private static func mapDetail(_ detail: Hiveng_V1_ErrorDetail, message: String) -> HiveAxylError {
        let meta = detail.metadata
        switch detail.code {
        case .playerBanned:
            let untilRaw = meta["until"] ?? meta["banned_until"]
            return .banned(
                reason: meta["reason"] ?? message,
                until: untilRaw.flatMap(RFC3339.parse),
                permanent: meta["permanent"] == "true"
            )
        case .geoBlocked:
            return .geoBlocked(country: meta["country"] ?? "")
        case .maintenanceInProgress:
            let info = MaintenanceInfo(
                startsAt: meta["starts_at"].flatMap(RFC3339.parse),
                endsAt: meta["ends_at"].flatMap(RFC3339.parse),
                messages: [:],
                message: message.isEmpty ? nil : message
            )
            return .maintenance(info)
        case .duplicateReceipt:
            return .duplicateReceipt
        default:
            return .code(detail.code, message: message)
        }
    }
}
