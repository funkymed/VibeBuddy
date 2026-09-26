import Foundation

/// The alerts waiting to be seen, one per session. What the tongue under the notch
/// shows: the most urgent, and how many others are behind it.
public struct AlertStack: Sendable, Equatable {
    /// One entry per session, the most recent it produced.
    public private(set) var entries: [SessionAlert] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// Waiting on an answer beats a failure, which beats a success; then the newest.
    public var head: SessionAlert? {
        entries.max { a, b in
            let ra = Self.rank(a.kind), rb = Self.rank(b.kind)
            return ra != rb ? ra < rb : a.at < b.at
        }
    }

    /// Replaces whatever this session had waiting: a session is in one state at a time.
    public mutating func push(_ alert: SessionAlert) {
        entries.removeAll { $0.sessionID == alert.sessionID }
        entries.append(alert)
    }

    public mutating func remove(sessionID: String) {
        entries.removeAll { $0.sessionID == sessionID }
    }

    /// Seen: the pointer opened the panel.
    public mutating func clear() { entries.removeAll() }

    /// Drops what a live session has moved on from. A session that is gone, or no longer
    /// listed, keeps its entry: it may have finished and then exited, and that is still
    /// news until someone looks.
    public mutating func prune(against sessions: [AgentSession]) {
        let byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entries.removeAll { alert in
            guard let session = byID[alert.sessionID], session.isLive else { return false }
            return SessionDisplayState.of(session) != Self.state(for: alert.kind)
        }
    }

    static func rank(_ kind: SessionAlert.Kind) -> Int {
        switch kind {
        case .needsAttention: return 2
        case .failed: return 1
        case .finished: return 0
        }
    }

    static func state(for kind: SessionAlert.Kind) -> SessionDisplayState {
        switch kind {
        case .finished: return .finished
        case .failed: return .failed
        case .needsAttention: return .awaiting
        }
    }
}
