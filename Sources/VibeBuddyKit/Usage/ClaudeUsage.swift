import Foundation

/// Live limit utilisation, as Anthropic's own billing page reports it.
///
/// Every field is optional. Verified 2026-08-19: the response carries windows
/// this build has never heard of (`tangelo`, `cinder_cove`), most of them null.
/// Render a missing one as "unavailable", never zero: 0 % looks like good news.
public struct ClaudeUsage: Sendable, Equatable, Codable {

    public struct Window: Sendable, Equatable, Codable {
        /// 0…100.
        public let utilisation: Double
        public let resetsAt: Date?

        public init(utilisation: Double, resetsAt: Date?) {
            self.utilisation = utilisation
            self.resetsAt = resetsAt
        }

        public var fraction: Double { min(1, max(0, utilisation / 100)) }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    public let sevenDaySonnet: Window?
    public let sevenDayOpus: Window?
    public let fetchedAt: Date

    public init(
        fiveHour: Window?, sevenDay: Window?,
        sevenDaySonnet: Window? = nil, sevenDayOpus: Window? = nil,
        fetchedAt: Date = Date()
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOpus = sevenDayOpus
        self.fetchedAt = fetchedAt
    }

    /// Unknown keys are ignored, not rejected: this is not a public contract.
    public static func parse(_ json: [String: Any], now: Date = Date()) -> ClaudeUsage {
        ClaudeUsage(
            fiveHour: window(json["five_hour"]),
            sevenDay: window(json["seven_day"]),
            sevenDaySonnet: window(json["seven_day_sonnet"]),
            sevenDayOpus: window(json["seven_day_opus"]),
            fetchedAt: now
        )
    }

    static func window(_ value: Any?) -> Window? {
        guard let dict = value as? [String: Any],
              let utilisation = dict["utilization"] as? Double
        else { return nil }
        let resets = (dict["resets_at"] as? String).flatMap(parseDate)
        return Window(utilisation: utilisation, resetsAt: resets)
    }

    /// `2026-08-19T22:20:00.226366+00:00` — fractional seconds, and an offset
    /// rather than `Z`. Both spellings occur, so both are accepted.
    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: text) { return d }
        return ISO8601DateFormatter().date(from: text)
    }
}

public enum UsageOutcome: Sendable, Equatable {
    case success(ClaudeUsage)
    /// Throttled. Honour `retryAfter`: hammering a rate limiter blocks a token.
    case rateLimited(retryAfter: TimeInterval)
    case noCredentials
    case failed(String)
}
