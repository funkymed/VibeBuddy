import Foundation

/// Sessions the user took off the list, and until when.
///
/// Nothing is deleted: a transcript is Claude Code's record of a conversation, not ours
/// to remove. A dismissal hides a row, and it lapses the moment the session writes
/// again — an abandoned agent never does, so it stays gone, while one dismissed by
/// mistake comes back on its next line.
@MainActor
public final class DismissedSessions {
    public enum Keys {
        public static let entries = "vibebuddy.sessions.dismissed"
    }

    /// Claude Code never deletes a transcript, so without a cap this grows for the life
    /// of the install. Oldest dismissals go first.
    public static let maxEntries = 200

    private let store: PreferencesStore
    private var dismissedAt: [String: Date] = [:]

    public init(store: PreferencesStore) {
        self.store = store
        reload()
    }

    public var count: Int { dismissedAt.count }

    /// Hidden while the session has not moved since it was dismissed.
    public func isDismissed(_ session: AgentSession) -> Bool {
        guard let at = dismissedAt[session.id] else { return false }
        return session.lastActivity <= at
    }

    public func dismiss(_ session: AgentSession, at now: Date = Date()) {
        // The session's own clock, never the wall clock alone: a transcript written a
        // second ago by a machine whose time differs would reappear at once.
        dismissedAt[session.id] = max(now, session.lastActivity)
        prune()
        persist()
    }

    public func restore(_ id: String) {
        guard dismissedAt.removeValue(forKey: id) != nil else { return }
        persist()
    }

    public func clear() {
        guard !dismissedAt.isEmpty else { return }
        dismissedAt = [:]
        persist()
    }

    public func filter(_ sessions: [AgentSession]) -> [AgentSession] {
        guard !dismissedAt.isEmpty else { return sessions }
        return sessions.filter { !isDismissed($0) }
    }

    public func reload() {
        guard let data = store.data(Keys.entries),
              let raw = try? JSONDecoder().decode([String: Date].self, from: data)
        else {
            dismissedAt = [:]
            return
        }
        dismissedAt = raw
    }

    private func prune() {
        guard dismissedAt.count > Self.maxEntries else { return }
        let keep = dismissedAt.sorted { $0.value > $1.value }.prefix(Self.maxEntries)
        dismissedAt = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(dismissedAt) else { return }
        store.set(data, forKey: Keys.entries)
    }
}
