import Testing
import Foundation
@testable import VibeBuddyKit

@MainActor
@Suite("Dismissing a session")
struct DismissedSessionsTests {
    private func store() -> PreferencesStore {
        let suite = "vb-dismiss-\(UUID().uuidString)"
        return PreferencesStore(defaults: UserDefaults(suiteName: suite)!, previous: [])
    }

    private func session(
        id: String = "s1", cwd: String = "/tmp/p", lastActivity: Date, live: Bool = false
    ) -> AgentSession {
        AgentSession(
            id: id, cwd: cwd, projectName: "p", model: "claude-opus-5",
            startedAt: lastActivity, lastActivity: lastActivity,
            status: nil, action: .none, permissionMode: "",
            contextTokens: 0, contextWindow: 200_000, pid: nil, isLive: live)
    }

    @Test("a session is listed until it is dismissed")
    func hides() {
        let dismissed = DismissedSessions(store: store())
        let s = session(lastActivity: Date())
        #expect(!dismissed.isDismissed(s))
        dismissed.dismiss(s)
        #expect(dismissed.isDismissed(s))
    }

    // The whole point of the feature: an abandoned agent stays live and never writes
    // again, so liveness must not bring the row back on its own.
    @Test("a live session that writes nothing more stays hidden")
    func staysHiddenWhileLive() {
        let dismissed = DismissedSessions(store: store())
        let s = session(lastActivity: Date(), live: true)
        dismissed.dismiss(s)
        #expect(dismissed.isDismissed(s))
        #expect(dismissed.filter([s]).isEmpty)
    }

    @Test("writing again brings it back")
    func returnsOnNewActivity() {
        let dismissed = DismissedSessions(store: store())
        let at = Date()
        dismissed.dismiss(session(lastActivity: at), at: at)
        let later = session(lastActivity: at.addingTimeInterval(30))
        #expect(!dismissed.isDismissed(later))
    }

    // Dismissing on a machine whose clock trails the transcript's own timestamps would
    // otherwise hide nothing at all.
    @Test("a transcript stamped in the future is still hidden")
    func clockSkew() {
        let dismissed = DismissedSessions(store: store())
        let ahead = session(lastActivity: Date().addingTimeInterval(600))
        dismissed.dismiss(ahead, at: Date())
        #expect(dismissed.isDismissed(ahead))
    }

    @Test("only the dismissed session goes")
    func filtersOne() {
        let dismissed = DismissedSessions(store: store())
        let now = Date()
        let a = session(id: "a", lastActivity: now)
        let b = session(id: "b", lastActivity: now)
        dismissed.dismiss(a)
        #expect(dismissed.filter([a, b]).map(\.id) == ["b"])
    }

    @Test("restoring puts it back")
    func restores() {
        let dismissed = DismissedSessions(store: store())
        let s = session(lastActivity: Date())
        dismissed.dismiss(s)
        dismissed.restore(s.id)
        #expect(!dismissed.isDismissed(s))
    }

    @Test("clearing empties the whole set")
    func clears() {
        let dismissed = DismissedSessions(store: store())
        dismissed.dismiss(session(id: "a", lastActivity: Date()))
        dismissed.dismiss(session(id: "b", lastActivity: Date()))
        dismissed.clear()
        #expect(dismissed.count == 0)
    }

    // Claude Code never deletes a transcript, so an uncapped set grows for the life of
    // the install.
    @Test("the set is capped, oldest dismissals first")
    func caps() {
        let dismissed = DismissedSessions(store: store())
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<(DismissedSessions.maxEntries + 20) {
            let at = base.addingTimeInterval(Double(i))
            dismissed.dismiss(session(id: "s\(i)", lastActivity: at), at: at)
        }
        #expect(dismissed.count == DismissedSessions.maxEntries)
        // The newest survives, the oldest is gone.
        #expect(dismissed.isDismissed(session(id: "s219", lastActivity: base)))
        #expect(!dismissed.isDismissed(session(id: "s0", lastActivity: base)))
    }

    @Test("dismissals survive a relaunch")
    func persists() {
        let suite = "vb-dismiss-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let s = session(lastActivity: Date())

        // Flushed through the store that holds the pending write: this one coalesces
        // for 250 ms, and the app's own safety net is the flush on terminate.
        let writer = PreferencesStore(defaults: defaults, previous: [])
        DismissedSessions(store: writer).dismiss(s)
        writer.flush()

        let second = DismissedSessions(store: PreferencesStore(defaults: defaults, previous: []))
        #expect(second.isDismissed(s))
    }
}
