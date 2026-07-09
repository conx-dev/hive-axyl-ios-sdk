import Foundation

enum RFC3339 {
    private static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        standard.date(from: raw) ?? fractional.date(from: raw)
    }

    static func format(_ date: Date) -> String {
        standard.string(from: date)
    }
}
