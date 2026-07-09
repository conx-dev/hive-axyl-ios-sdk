import Foundation
import SwiftProtobuf

public struct Player: Equatable {
    public let playerId: String
    public let projectId: String
    public let country: String
    public let email: String
    public let nickname: String
    public let lastLoginPlatform: String
    // 연결된 로그인 수단의 소문자 이름 (예: "google")
    public let providers: [String]
    public let createdAt: Date?
    public let lastLoginAt: Date?
}

public struct LoginProviders: Equatable {
    public let providers: [String]
    public let country: String
}

public struct Notice: Equatable {
    public let id: String
    public let projectId: String
    public let title: String
    public let body: String
    public let startsAt: Date?
    public let endsAt: Date?
    public let viewCount: Int64
}

public struct Mail: Equatable {
    public let id: String
    public let mailID: String
    public let projectID: String
    public let type: Hiveng_V1_MailType
    public let title: String
    public let body: String
    public let sender: String
    public let rewardPreview: [String: String]
    public let claimed: Bool
    public let claimableFrom: Date?
    public let expiresAt: Date?
    public let claimedAt: Date?
    public let createdAt: Date?
}

public struct PaymentPurchase: Equatable {
    public let id: String
    public let projectID: String
    public let playerID: String
    public let market: String
    public let productType: String
    public let productID: String
    public let packageName: String
    public let purchaseIntentID: String
    public let amountMinor: Int64
    public let currency: String
    public let status: String
    public let grantStatus: String
    public let consumeStatus: String
    public let marketOrderID: String
    public let purchasedAt: Date?
    public let verifiedAt: Date?
}

public enum PaymentProductType: Equatable {
    case oneTime
    case subscription
}

public struct PaymentProduct: Equatable {
    public let productID: String
    public let productType: PaymentProductType
    public let appIdentifier: String
    public let marketStatus: String
    public let title: String
    public let description: String
    public let enabled: Bool
}

public struct PushTarget: Equatable {
    public let id: String
    public let projectID: String
    public let playerID: String
    public let fid: String
    public let tokenPreview: String
    public let platform: String
    public let appIdentifier: String
    public let language: String
    public let enabled: Bool
    public let lastSeenAt: Date?
    public let createdAt: Date?
    public let updatedAt: Date?
}

extension Player {
    init(message: Hiveng_V1_Player) {
        playerId = message.playerID
        projectId = message.projectID
        country = message.country
        email = message.email
        nickname = message.nickname
        lastLoginPlatform = ClientPlatformName.of(message.lastLoginPlatform)
        providers = message.providers.map(ProviderName.of)
        createdAt = message.hasCreatedAt ? message.createdAt.dateValue : nil
        lastLoginAt = message.hasLastLoginAt ? message.lastLoginAt.dateValue : nil
    }
}

extension LoginProviders {
    init(message: Hiveng_V1_GetLoginProvidersResponse) {
        providers = message.providers.map(ProviderName.of)
        country = message.country
    }
}

extension Notice {
    init(message: Hiveng_V1_Notice, language: String) {
        id = message.id
        projectId = message.projectID
        title = LocalizedText.resolve(message.title, language: language)
        body = LocalizedText.resolve(message.body, language: language)
        startsAt = message.hasStartsAt ? message.startsAt.dateValue : nil
        endsAt = message.hasEndsAt ? message.endsAt.dateValue : nil
        viewCount = message.viewCount
    }
}

extension Mail {
    init(message: Hiveng_V1_Mail, language: String) {
        id = message.id
        mailID = message.mailID
        projectID = message.projectID
        type = message.type
        title = LocalizedText.resolve(message.title, language: language)
        body = LocalizedText.resolve(message.body, language: language)
        sender = message.sender
        rewardPreview = message.rewardPreview
        claimed = message.claimed
        claimableFrom = message.hasClaimableFrom ? message.claimableFrom.dateValue : nil
        expiresAt = message.hasExpiresAt ? message.expiresAt.dateValue : nil
        claimedAt = message.hasClaimedAt ? message.claimedAt.dateValue : nil
        createdAt = message.hasCreatedAt ? message.createdAt.dateValue : nil
    }
}

extension PaymentPurchase {
    init(message: Hiveng_V1_Purchase) {
        id = message.id
        projectID = message.projectID
        playerID = message.playerID
        market = MarketName.of(message.market)
        productType = ProductTypeName.of(message.productType)
        productID = message.productID
        packageName = message.packageName
        purchaseIntentID = message.purchaseIntentID
        amountMinor = message.amountMinor
        currency = message.currency
        status = PurchaseStatusName.of(message.status)
        grantStatus = message.grantStatus
        consumeStatus = message.consumeStatus
        marketOrderID = message.marketOrderID
        purchasedAt = message.hasPurchasedAt ? message.purchasedAt.dateValue : nil
        verifiedAt = message.hasVerifiedAt ? message.verifiedAt.dateValue : nil
    }
}

extension PaymentProduct {
    init(message: Hiveng_V1_PaymentProduct) {
        productID = message.productID
        productType = PaymentProductType(message: message.productType)
        appIdentifier = message.appIdentifier
        marketStatus = message.marketStatus
        title = message.title
        description = message.description_p
        enabled = message.enabled
    }
}

extension PushTarget {
    init(message: Hiveng_V1_PushTarget) {
        id = message.id
        projectID = message.projectID
        playerID = message.playerID
        fid = message.fid
        tokenPreview = message.tokenPreview
        platform = message.platform
        appIdentifier = message.appIdentifier
        language = message.language
        enabled = message.enabled
        lastSeenAt = message.hasLastSeenAt ? message.lastSeenAt.dateValue : nil
        createdAt = message.hasCreatedAt ? message.createdAt.dateValue : nil
        updatedAt = message.hasUpdatedAt ? message.updatedAt.dateValue : nil
    }
}

extension PaymentProductType {
    init(message: Hiveng_V1_ProductType) {
        if message == .subscription {
            self = .subscription
            return
        }
        self = .oneTime
    }
}

enum ProviderName {
    private static let names: [Hiveng_V1_IdentityProvider: String] = [
        .unspecified: "unspecified",
        .kakao: "kakao",
        .naver: "naver",
        .google: "google",
        .facebook: "facebook",
        .apple: "apple",
        .line: "line",
        .truecaller: "truecaller",
        .phoneOtp: "phone_otp",
        .guest: "guest",
    ]

    static func of(_ provider: Hiveng_V1_IdentityProvider) -> String {
        names[provider] ?? "unspecified"
    }
}

enum ClientPlatformName {
    private static let names: [Hiveng_V1_ClientPlatform: String] = [
        .unspecified: "unspecified",
        .web: "web",
        .android: "android",
        .ios: "ios",
    ]

    static func of(_ platform: Hiveng_V1_ClientPlatform) -> String {
        names[platform] ?? "unspecified"
    }
}

enum MarketName {
    private static let names: [Hiveng_V1_Market: String] = [
        .googlePlay: "google_play",
        .appStore: "app_store",
        .steam: "steam",
        .web: "web",
    ]

    static func of(_ market: Hiveng_V1_Market) -> String {
        names[market] ?? "unspecified"
    }
}

enum ProductTypeName {
    private static let names: [Hiveng_V1_ProductType: String] = [
        .oneTime: "one_time",
        .subscription: "subscription",
    ]

    static func of(_ productType: Hiveng_V1_ProductType) -> String {
        names[productType] ?? "unspecified"
    }
}

enum PurchaseStatusName {
    private static let names: [Hiveng_V1_PurchaseStatus: String] = [
        .pending: "pending",
        .verified: "verified",
        .failed: "failed",
        .refunded: "refunded",
        .canceled: "canceled",
        .expired: "expired",
    ]

    static func of(_ status: Hiveng_V1_PurchaseStatus) -> String {
        names[status] ?? "unspecified"
    }
}

enum LocalizedText {
    static func resolve(_ values: [String: String], language: String) -> String {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            if let exact = values[normalized] {
                return exact
            }
            if let dash = normalized.firstIndex(of: "-") {
                let base = String(normalized[..<dash])
                if let baseMatch = values[base] {
                    return baseMatch
                }
            }
        }
        if let english = values["en"] {
            return english
        }
        if let korean = values["ko"] {
            return korean
        }
        guard let firstKey = values.keys.sorted().first else {
            return ""
        }
        return values[firstKey] ?? ""
    }
}

extension SwiftProtobuf.Google_Protobuf_Timestamp {
    var dateValue: Date {
        Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
    }
}
