import Foundation
import Observation

/// Holds the latest usage reading, and decides when to ask again.
///
/// Cadence is adaptive because a five-hour window does not move fast enough to
/// justify polling it steadily: 180 s while the panel is shut, 30 s while it is
/// open, 10 s while we have nothing at all. The reference implementation polls
/// every 60 s regardless, which is both slower to first result and busier at
/// rest.
///
/// This is the app's **only** unconditional periodic wake — RFC-001, D3.
@MainActor
@Observable
public final class UsageState {

    public enum Status: Sendable, Equatable {
        case unknown
        case ready(ClaudeUsage)
        case unavailable(String)
    }

    public private(set) var status: Status = .unknown

    /// When we may ask again. Moved forward by rate limiting.
    private var nextAttempt: Date = .distantPast
    /// Consecutive refusals, for the backoff.
    private(set) var consecutiveLimits = 0
    private let client: UsageClient

    /// First delay after a refusal, and the ceiling the doubling stops at.
    ///
    /// Measured on 2026-08-20: the endpoint answers `429` with
    /// `retry-after: 0` and `{"type":"rate_limit_error"}`. Zero is not a
    /// schedule — a server that refuses and says "try immediately" will refuse
    /// the immediate retry too, and a client that obeys it turns one refusal
    /// into a loop that keeps the limiter warm. So the header is treated as a
    /// floor, never as permission.
    public static let backoffFloor: TimeInterval = 60
    public static let backoffCeiling: TimeInterval = 900

    public var isPanelOpen = false

    /// - Parameter seeded: a starting reading.
    ///
    /// Exists so tests can exercise "what happens to an existing reading when
    /// the next fetch fails" without a live network. The setter stays private:
    /// the point is to seed at construction, not to let anything write status
    /// behind the state machine's back.
    private let cache: UsageCache?

    public init(
        client: UsageClient = UsageClient(),
        seeded: Status = .unknown,
        cache: UsageCache? = UsageCache()
    ) {
        self.client = client
        self.cache = cache
        // A reading from the last launch beats an empty gauge while the first
        // fetch is in flight — or refused.
        if case .unknown = seeded, let stored = cache?.load() {
            self.status = .ready(stored)
        } else {
            self.status = seeded
        }
    }

    public var usage: ClaudeUsage? {
        if case let .ready(usage) = status { return usage }
        return nil
    }

    /// Interval before the next attempt, given what we know.
    public var interval: TimeInterval {
        // Being throttled is its own schedule: exponential, and independent of
        // whether the panel happens to be open.
        if consecutiveLimits > 0 { return backoff }
        switch status {
        case .unknown, .unavailable: return 10
        case .ready: return isPanelOpen ? 30 : 180
        }
    }

    /// 60 s, 120, 240… capped at 15 minutes.
    var backoff: TimeInterval {
        let doublings = min(consecutiveLimits - 1, 8)
        return min(Self.backoffFloor * pow(2, Double(max(0, doublings))), Self.backoffCeiling)
    }

    /// Seams for the schedule tests. Named so nobody mistakes them for API:
    /// the counter is owned by `refresh`, and nothing else may move it.
    func setLimitsForTesting(_ count: Int) { consecutiveLimits = count }
    func clearLimitsForTesting() { consecutiveLimits = 0 }

    /// How stale the reading on screen is, or nil when there is none.
    ///
    /// Surfaced rather than hidden: a five-hour window read twenty minutes ago
    /// is still worth showing, and pretending it is current is exactly the kind
    /// of plausible-but-wrong number this product exists to replace.
    public func age(now: Date = Date()) -> TimeInterval? {
        guard case let .ready(usage) = status else { return nil }
        return now.timeIntervalSince(usage.fetchedAt)
    }

    /// Ask, unless it is too soon or we are still being throttled.
    public func refresh(now: Date = Date()) async {
        guard now >= nextAttempt else { return }
        nextAttempt = now.addingTimeInterval(interval)

        switch await client.fetch(now: now) {
        case let .success(usage):
            consecutiveLimits = 0
            status = .ready(usage)
            cache?.save(usage)
        case let .rateLimited(retryAfter):
            consecutiveLimits += 1
            // The server's own delay if it asked for a real one, our backoff
            // otherwise — whichever is longer.
            nextAttempt = now.addingTimeInterval(max(retryAfter, backoff))
            if case .ready = status { break }   // keep showing the last good reading
            status = .unavailable("limité")
        case .noCredentials:
            status = .unavailable("non connecté")
        case let .failed(reason):
            // A network blip should not blank a reading that was fine a minute
            // ago; only replace it if we never had one.
            if case .ready = status { break }
            status = .unavailable(reason)
        }
    }
}
