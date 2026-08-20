import Foundation

/// Sessions of one project, collapsed into a single row.
///
/// # Why group at all
///
/// Claude Code never deletes a transcript, and a project accumulates them: five
/// runs in the same directory produce five entries, four of them finished. Shown
/// flat, a single afternoon of work buries the session actually running under
/// its own history — which is the opposite of what a dashboard is for.
///
/// Grouping by working directory is the right key rather than by session id:
/// what the user thinks of as "my notch session" is the directory, and the ids
/// change every time they restart.
public struct SessionGroup: Sendable, Equatable, Identifiable {

    public let cwd: String
    /// The one worth showing: live first, then most recently active.
    public let primary: AgentSession
    /// Everything in the group, primary included.
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

    /// Group and order for display.
    ///
    /// Within a group the live session wins, then the most recent — a finished
    /// run must never mask a running one. Between groups, the same rule.
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

    /// One group per session, same ordering.
    ///
    /// The preference to *not* group still goes through `SessionGroup`, rather
    /// than the view growing a second path for bare sessions: the row's badges,
    /// its equality and its jump all read a group, and two shapes for the same
    /// row is how a list ends up with two behaviours.
    ///
    /// Keyed by session id, because two ungrouped rows in one directory must
    /// not collide on `id` — `ForEach` would drop one of them.
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
