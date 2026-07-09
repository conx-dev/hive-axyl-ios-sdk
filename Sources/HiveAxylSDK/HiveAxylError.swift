import Foundation

public struct MaintenanceInfo: Equatable {
    public let startsAt: Date?
    public let endsAt: Date?
    public let messages: [String: String]
    public let message: String?

    public init(startsAt: Date?, endsAt: Date?, messages: [String: String], message: String?) {
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.messages = messages
        self.message = message
    }
}

public enum HiveAxylError: Error, Equatable {
    case notInitialized
    case invalidArgument(String)
    case maintenance(MaintenanceInfo)
    case geoBlocked(country: String)
    case banned(reason: String, until: Date?, permanent: Bool)
    case duplicateReceipt
    case code(Hiveng_V1_ErrorCode, message: String)
    case transport(String)
}
