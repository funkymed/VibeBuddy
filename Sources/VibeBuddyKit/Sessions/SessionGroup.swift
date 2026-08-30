import Foundation

/// Keyed by working directory, not by session id: the ids change on every restart.
public struct SessionGroup: Sendable, Equatable, Identifiable {
    public let cwd: String
    public let primary: AgentSession
    public let all: [AgentSession]

    /// Identity of the row, not of the folder: several live sessions can share a `cwd`,
    /// and `ForEach` drops rows whose ids collide.
    public var id: String { primary.id }
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
        // Two rows carrying the same `id` is not a display bug, it is a vanished row:
        // `ForEach` keeps one and silently drops the other. A session id can turn up
        // twice when the same session has written under two working directories.
        var seen = Set<String>()
        for session in sessions where seen.insert(session.id).inserted {
            byDirectory[session.cwd, default: []].append(session)
        }

        var rows: [SessionGroup] = []
        for (cwd, members) in byDirectory {
            let ranked = members.sorted(by: byRelevance)
            let live = ranked.filter(\.isLive)
            guard !live.isEmpty else {
                // Nothing running here: the whole history is one row.
                if let primary = ranked.first {
                    rows.append(SessionGroup(cwd: cwd, primary: primary, all: ranked))
                }
                continue
            }
            let dead = ranked.filter { !$0.isLive }
            for (index, session) in live.enumerated() {
                // The history rides on the first row of the folder only, so the `×n`
                // badge appears once instead of on every sibling.
                let all = index == 0 ? [session] + dead : [session]
                rows.append(SessionGroup(cwd: cwd, primary: session, all: all))
            }
        }
        return rows.sorted { byRelevance($0.primary, $1.primary) }
    }

    /// Keyed by session id: two ungrouped rows in one directory must not collide on
    /// `id`, or `ForEach` drops one of them.
    public static func ungrouped(_ sessions: [AgentSession]) -> [SessionGroup] {
        var seen = Set<String>()
        return sessions.sorted(by: byRelevance)
            .filter { seen.insert($0.id).inserted }
            .map { SessionGroup(cwd: $0.cwd, primary: $0, all: [$0]) }
    }

    static func byRelevance(_ a: AgentSession, _ b: AgentSession) -> Bool {
        if a.isLive != b.isLive { return a.isLive }
        return a.lastActivity > b.lastActivity
    }
}
