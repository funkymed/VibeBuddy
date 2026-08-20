import Foundation

/// Live limit utilisation, as Anthropic's own billing page reports it.
///
/// Every field is optional, deliberately. Verified against the live endpoint on
/// 2026-08-19: the response carries windows this build has never heard of —
/// `tangelo`, `nimbus_quill`, `omelette_promotional`, `cinder_cove` — most of
/// them null. Names appear and disappear as plans change, so a parser that
/// insists on a shape breaks the day one is renamed.
///
/// A missing window renders as "unavailable", never as zero. Showing 0 % when
/// the truth is unknown is worse than showing nothing, because 0 % looks like
/// good news.
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

    /// The rolling five-hour session limit.
    public let fiveHour: Window?
    /// The weekly limit across all models.
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

    /// Parse whatever of the response we recognise.
    ///
    /// Unknown keys are ignored rather than rejected: this endpoint is not a
    /// public contract, and the alternative to ignoring them is showing nothing
    /// the day a new one appears.
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

/// What happened when we asked.
public enum UsageOutcome: Sendable, Equatable {
    case success(ClaudeUsage)
    /// Throttled. `retryAfter` is what the server asked for, honoured rather
    /// than guessed — hammering a rate limiter is how a token gets blocked.
    case rateLimited(retryAfter: TimeInterval)
    /// No token, or an expired one. Claude Code refreshes its own; we only read.
    case noCredentials
    case failed(String)
}
