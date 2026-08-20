import Foundation
import NotchBuddyKit

/// Drives `SessionStore` from its two clocks.
///
/// Transcript changes arrive from FSEvents and cost nothing while nothing is
/// written. Process liveness has no such signal — a process exiting emits no
/// filesystem event — so it is polled, but lazily: 30 s while nothing is
/// happening, 2 s once a session is live.
///
/// That cadence switch is the whole reason this class exists rather than the
/// store driving itself: the store should not know about wake budgets.
@MainActor
final class SessionCoordinator {

    private let store: SessionStore
    private let wake: WakeCoordinator
    private var watcher: ProjectsWatcher?
    private let id = "sessions"

    private(set) var sessions: [AgentSession] = []
    var onChange: (([AgentSession]) -> Void)?
    var onChangeLog: (([AgentSession]) -> Void)?

    /// RFC-012. Created here rather than injected because the tracker's state is
    /// meaningless without the snapshots that feed it.
    let alerts = AlertBus()
    private let tracker: AlertTracker
    var onAlert: ((SessionAlert) -> Void)?
    /// RFC-010 preference, pushed rather than observed: this is read inside a
    /// closure the tracker owns, and an `@Observable` read there would tie the
    /// tracker's lifetime to a preference model it has no reason to know.
    var quietWhenTerminalFrontmost = true
    /// Alerts the policy chose not to show, with the reason. Exposed because a
    /// notification system that drops things silently cannot be trusted.
    var suppressedAlerts: [(alert: SessionAlert, reason: String)] { tracker.suppressed }

    init(wake: WakeCoordinator, store: SessionStore = SessionStore()) {
        self.wake = wake
        self.store = store
        self.tracker = AlertTracker(bus: alerts)
        self.tracker.isHostingTerminalFrontmost = { [weak self] session in
            // The preference can turn this suppression off entirely. On a second
            // display the "frontmost" terminal can be a screen away, which is
            // the case someone would reasonably disagree with.
            guard self?.quietWhenTerminalFrontmost ?? true else { return false }
            guard let pid = session.pid else { return false }
            return TerminalFocusProbe.isHostingTerminalFrontmost(agentPID: pid)
        }
    }

    func start() {
        let root = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")

        watcher = ProjectsWatcher { [weak self] changed in
            // FSEvents delivers on its own queue; the refresh hops to the store.
            // The paths let the store re-read a handful of files instead of
            // walking the whole corpus.
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

    private func refresh(changed: [String]? = nil) async {
        let updated = await store.refresh(changed: changed)
        guard updated != sessions else { return }
        sessions = updated

        // Live sessions justify a tighter liveness poll; nothing running does
        // not. This is the only place the cadence moves.
        let live = updated.contains(where: \.isLive)
        wake.setCadence(live ? .active : .lazy, for: id)

        for alert in tracker.ingest(updated) { onAlert?(alert) }
        onChange?(updated)
        onChangeLog?(updated)
    }
}
