import Foundation

/// Keyed by working directory, not by session id: the ids change on every restart.
/// See RFC-003, « Notes d'implémentation ».
public struct SessionGroup: Sendable, Equatable, Identifiable {

    public let cwd: String
    public let primary: AgentSession
    public let all: [AgentSession]

    public var id: String { cwd }
    public var count: Int { all.count }
    public var liveCount: Int { all.filter(\.isLive).count }
    public var hasHistory: Bool { count > 1 }

    public init(cwd: String, primary: AgentSession, all: [AgentSession]) {
        self.cwd = cwd
        self.primary = primary
        self.all = all
    }

    /// Live first, then most recent — a finished run must never mask a running one.
    public static func group(_ sessions: [AgentSession]) -> [SessionGroup] {
        var byDirectory: [String: [AgentSession]] = [:]
        for session in sessions {
            byDirectory[session.cwd, default: []].append(session)
        }

        return byDirectory.compactMap { cwd, members -> SessionGroup? in
            let ranked = members.sorted(by: byRelevance)
            guard let primary = ranked.first else { return nil }
            return SessionGroup(cwd: cwd, primary: primary, all: ranked)
        }
        .sorted { byRelevance($0.primary, $1.primary) }
    }

    /// Keyed by session id: two ungrouped rows in one directory must not collide on
    /// `id`, or `ForEach` drops one of them.
    public static func ungrouped(_ sessions: [AgentSession]) -> [SessionGroup] {
        sessions.sorted(by: byRelevance).map {
            SessionGroup(cwd: $0.id, primary: $0, all: [$0])
        }
    }

    static func byRelevance(_ a: AgentSession, _ b: AgentSession) -> Bool {
        if a.isLive != b.isLive { return a.isLive }
        return a.lastActivity > b.lastActivity
    }
}
