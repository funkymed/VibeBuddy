import Foundation
import VibeBuddyKit

/// Drives `SessionStore` from its two clocks: FSEvents for transcript changes, and a
/// poll for liveness — a process exiting emits no filesystem event. 30 s while idle, 2 s
/// once a session is live.
@MainActor
final class SessionCoordinator {
    private let store: SessionStore
    private let wake: WakeCoordinator
    private var watcher: ProjectsWatcher?
    private let id = "sessions"

    private(set) var sessions: [AgentSession] = []
    var onChange: (([AgentSession]) -> Void)?
    var onChangeLog: (([AgentSession]) -> Void)?

    let alerts = AlertBus()
    private let tracker: AlertTracker
    var onAlert: ((SessionAlert) -> Void)?
    /// Pushed rather than observed: an `@Observable` read inside the tracker's closure
    /// would tie its lifetime to a preference model.
    var quietWhenTerminalFrontmost = true
    /// Rows the user took off the list.
    var dismissed: DismissedSessions?
    /// Alerts the policy chose not to show, with the reason.
    var suppressedAlerts: [(alert: SessionAlert, reason: String)] { tracker.suppressed }

    init(wake: WakeCoordinator, store: SessionStore = SessionStore()) {
        self.wake = wake
        self.store = store
        self.tracker = AlertTracker(bus: alerts)
        self.tracker.isHostingTerminalFrontmost = { [weak self] session in
            // On a second display the "frontmost" terminal can be a screen away.
            guard self?.quietWhenTerminalFrontmost ?? true else { return false }
            guard let pid = session.pid else { return false }
            return TerminalFocusProbe.isHostingTerminalFrontmost(agentPID: pid)
        }
    }

    func start() {
        let root = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")

        watcher = ProjectsWatcher { [weak self] changed in
            // The paths let the store re-read a few files, not the whole corpus.
            Task { await self?.refresh(changed: changed) }
        }
        watcher?.start(path: root)

        wake.register(id: id, cadence: .lazy) { [weak self] in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        wake.unregister(id: id)
    }

    /// Takes a session off the list and republishes at once, rather than waiting for
    /// the next tick to make the click look like it worked.
    func dismiss(_ session: AgentSession) {
        dismissed?.dismiss(session)
        Task { await refresh() }
    }

    /// Puts every hidden row back.
    func restoreDismissed() {
        dismissed?.clear()
        Task { await refresh() }
    }

    private func refresh(changed: [String]? = nil) async {
        let all = await store.refresh(changed: changed)
        // Filtered here and nowhere else: the pill's count, the face, the alerts and the
        // list all read this one array, and two sources for one fact end up disagreeing.
        let updated = dismissed?.filter(all) ?? all
        guard updated != sessions else { return }
        sessions = updated

        // The only place the liveness cadence moves.
        let live = updated.contains(where: \.isLive)
        wake.setCadence(live ? .active : .lazy, for: id)

        for alert in tracker.ingest(updated) { onAlert?(alert) }
        onChange?(updated)
        onChangeLog?(updated)
    }
}
