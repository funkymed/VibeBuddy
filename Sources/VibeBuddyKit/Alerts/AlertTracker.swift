import Foundation

/// Keeps one state per session and turns snapshots into alerts.
///
/// N sessions, N independent state machines. The reference implementation keeps
/// a single "current" notion and loses everything but the newest session; here
/// three agents finishing in three projects produce three attributed alerts,
/// which is the whole point of watching more than one.
@MainActor
public final class AlertTracker {

    private var states: [String: SessionActivity] = [:]
    private var policy = AlertPolicy()
    private let bus: AlertBus

    /// Asked, per session, whether the user is already looking at that
    /// terminal. Injected so the tracker stays testable without AppKit.
    public var isHostingTerminalFrontmost: (AgentSession) -> Bool = { _ in false }

    /// Alerts the policy chose to suppress, and why. Surfaced in diagnostics:
    /// a notification system that silently drops things is impossible to trust.
    private(set) public var suppressed: [(alert: SessionAlert, reason: String)] = []

    public init(bus: AlertBus) {
        self.bus = bus
    }

    /// Feed a fresh snapshot of every known session.
    @discardableResult
    public func ingest(_ sessions: [AgentSession], now: Date = Date()) -> [SessionAlert] {
        var published: [SessionAlert] = []
        var seen = Set<String>()

        for session in sessions {
            seen.insert(session.id)
            let current = states[session.id] ?? .idle
            let observation = SessionObservation(
                sessionID: session.id,
                projectName: session.projectName,
                action: session.action,
                turnEnded: session.turnEnded,
                lastResultWasError: session.lastResultWasError,
                subagentsRunning: session.subagentsRunning,
                isLive: session.isLive,
                at: session.lastActivity,
                awaitingAnswer: session.awaitingAnswer
            )

            let step = SessionStateMachine.advance(from: current, observing: observation)
            states[session.id] = step.state

            guard let kind = step.alert else { continue }
            let alert = SessionAlert(
                sessionID: session.id, projectName: session.projectName,
                kind: kind, at: now
            )
            let decision = policy.admit(
                alert, now: now,
                hostingTerminalIsFrontmost: isHostingTerminalFrontmost(session)
            )
            if decision.allowed {
                bus.publish(alert)
                published.append(alert)
            } else {
                suppressed.append((alert, decision.reason))
                if suppressed.count > 20 { suppressed.removeFirst() }
            }
        }

        // Sessions that vanished lose their state, so a transcript reappearing
        // later starts clean rather than re-alerting from a stale one.
        states = states.filter { seen.contains($0.key) }
        return published
    }

    public func state(of sessionID: String) -> SessionActivity {
        states[sessionID] ?? .idle
    }

    public var trackedSessions: Int { states.count }
}
