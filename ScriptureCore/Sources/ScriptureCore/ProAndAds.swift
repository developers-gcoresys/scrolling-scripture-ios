import Foundation

/// Interaction-triggered interstitial policy shared by the reader and tests.
/// Mirrors the Android behavior: an ad is eligible after N page changes, at most
/// once per cooldown window, and at most M times per app session.
public struct AdSession: Sendable, Equatable {
    public let swipesPerAd: Int
    public let cooldown: TimeInterval
    public let maxAdsPerSession: Int

    public private(set) var swipesSinceAd: Int
    public private(set) var adsShown: Int
    public private(set) var lastAdAt: Date?

    public init(swipesPerAd: Int = 12, cooldown: TimeInterval = 300, maxAdsPerSession: Int = 2) {
        self.swipesPerAd = swipesPerAd
        self.cooldown = cooldown
        self.maxAdsPerSession = maxAdsPerSession
        self.swipesSinceAd = 0
        self.adsShown = 0
        self.lastAdAt = nil
    }

    public var adsRemaining: Int { max(0, maxAdsPerSession - adsShown) }

    /// Records a user interaction and returns true when an interstitial is due.
    /// The caller must call `markAdShown(at:)` only if an ad was actually shown.
    public mutating func recordPageChange(at date: Date) -> Bool {
        guard adsShown < maxAdsPerSession else { return false }
        swipesSinceAd += 1
        guard swipesSinceAd >= swipesPerAd else { return false }
        if let lastAdAt, date.timeIntervalSince(lastAdAt) < cooldown { return false }
        return true
    }

    public mutating func markAdShown(at date: Date) {
        adsShown += 1
        swipesSinceAd = 0
        lastAdAt = date
    }
}

public struct ProProductIDs: Sendable {
    public static let monthly = "pro_monthly"
    public static let yearly = "pro_yearly"
    public static let all = [monthly, yearly]
    public let monthly: String
    public let yearly: String

    public init(monthly: String = ProProductIDs.monthly, yearly: String = ProProductIDs.yearly) {
        self.monthly = monthly
        self.yearly = yearly
    }
}

public enum ScriptureISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }
}

/// Server-verified Pro state. This value is display state only; purchase and
/// feature checks must always come from the backend response.
public struct ProEntitlement: Codable, Equatable, Sendable {
    public let appId: String
    public let isPro: Bool
    public let status: String
    public let productId: String?
    public let expiresAt: Date?
    public let willRenew: Bool

    public init(appId: String, isPro: Bool, status: String, productId: String?, expiresAt: Date?, willRenew: Bool) {
        self.appId = appId
        self.isPro = isPro
        self.status = status
        self.productId = productId
        self.expiresAt = expiresAt
        self.willRenew = willRenew
    }

    public static let inactive = ProEntitlement(
        appId: "",
        isPro: false,
        status: "inactive",
        productId: nil,
        expiresAt: nil,
        willRenew: false
    )

    public func isActivePro(at date: Date = Date()) -> Bool {
        guard isPro else { return false }
        guard let expiresAt else { return false }
        return expiresAt > date
    }

    public static func decode(from data: Data) throws -> ProEntitlement {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ScriptureISO8601.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return try decoder.decode(ProEntitlement.self, from: data)
    }
}
