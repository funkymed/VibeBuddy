import Foundation
import Observation

/// Holds the latest usage reading, and decides when to ask again. Adaptive cadence: 180
/// s panel shut, 30 s panel open, 10 s with nothing yet.
@MainActor
@Observable
public final class UsageState {
    public enum Status: Sendable, Equatable {
        case unknown
        case ready(ClaudeUsage)
        case unavailable(String)
    }

    public private(set) var status: Status = .unknown

    private var nextAttempt: Date = .distantPast
    private(set) var consecutiveLimits = 0
    private let client: UsageClient

    /// First delay after a refusal, and the ceiling the doubling stops at.
    public static let backoffFloor: TimeInterval = 60
    public static let backoffCeiling: TimeInterval = 900

    public var isPanelOpen = false

    private let cache: UsageCache?

    public init(
        client: UsageClient = UsageClient(),
        seeded: Status = .unknown,
        cache: UsageCache? = UsageCache()
    ) {
        self.client = client
        self.cache = cache
        // A reading from the last launch beats an empty gauge while fetching.
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

    public var interval: TimeInterval {
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

    func setLimitsForTesting(_ count: Int) { consecutiveLimits = count }
    func clearLimitsForTesting() { consecutiveLimits = 0 }

    public func age(now: Date = Date()) -> TimeInterval? {
        guard case let .ready(usage) = status else { return nil }
        return now.timeIntervalSince(usage.fetchedAt)
    }

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
            // The server's delay or our backoff, whichever is longer.
            nextAttempt = now.addingTimeInterval(max(retryAfter, backoff))
            if case .ready = status { break }   // keep showing the last good reading
            status = .unavailable("limité")
        case .noCredentials:
            status = .unavailable("non connecté")
        case let .failed(reason):
            // A network blip must not blank a reading that was fine a minute ago.
            if case .ready = status { break }
            status = .unavailable(reason)
        }
    }
}
