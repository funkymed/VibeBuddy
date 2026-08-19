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
    private let client: UsageClient

    public var isPanelOpen = false

    /// - Parameter seeded: a starting reading.
    ///
    /// Exists so tests can exercise "what happens to an existing reading when
    /// the next fetch fails" without a live network. The setter stays private:
    /// the point is to seed at construction, not to let anything write status
    /// behind the state machine's back.
    public init(client: UsageClient = UsageClient(), seeded: Status = .unknown) {
        self.client = client
        self.status = seeded
    }

    public var usage: ClaudeUsage? {
        if case let .ready(usage) = status { return usage }
        return nil
    }

    /// Interval before the next attempt, given what we know.
    public var interval: TimeInterval {
        switch status {
        case .unknown, .unavailable: return 10
        case .ready: return isPanelOpen ? 30 : 180
        }
    }

    /// Ask, unless it is too soon or we are still being throttled.
    public func refresh(now: Date = Date()) async {
        guard now >= nextAttempt else { return }
        nextAttempt = now.addingTimeInterval(interval)

        switch await client.fetch(now: now) {
        case let .success(usage):
            status = .ready(usage)
        case let .rateLimited(retryAfter):
            // Honour what the server asked for rather than our own schedule.
            nextAttempt = now.addingTimeInterval(max(retryAfter, interval))
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
