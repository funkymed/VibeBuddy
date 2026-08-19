import Testing
import Foundation
@testable import NotchBuddyKit

private func session(
    _ id: String, project: String = "notch",
    action: ToolAction = .none, turnEnded: Bool = false,
    error: Bool = false, subagents: Int = 0, live: Bool = true
) -> AgentSession {
    AgentSession(
        id: id, cwd: "/Users/dev/\(project)", projectName: project,
        model: "claude-opus-5", startedAt: Date(), lastActivity: Date(),
        status: "", action: action, permissionMode: "auto",
        contextTokens: 1000, contextWindow: 200_000, pid: 1234, isLive: live,
        turnEnded: turnEnded, lastResultWasError: error, subagentsRunning: subagents
    )
}

@Suite("SessionAlert policy")
struct AlertPolicyTests {

    private func alert(_ id: String = "s1", _ kind: SessionAlert.Kind = .finished) -> SessionAlert {
        SessionAlert(sessionID: id, projectName: "notch", kind: kind, at: Date())
    }

    @Test("the first alert gets through")
    func firstPasses() {
        var policy = AlertPolicy()
        #expect(policy.admit(alert(), now: Date(), hostingTerminalIsFrontmost: false).allowed)
    }

    // The suppression that matters most: notifying someone about the window
    // they are already staring at is the fastest way to teach them to ignore
    // notifications entirely.
    @Test("nothing is said about a terminal the user is already looking at")
    func frontmostSuppresses() {
        var policy = AlertPolicy()
        let decision = policy.admit(alert(), now: Date(), hostingTerminalIsFrontmost: true)
        #expect(!decision.allowed)
        #expect(decision.reason == "terminal au premier plan")
    }

    @Test("the same alert twice in the window is one alert")
    func dedupe() {
        var policy = AlertPolicy()
        let t0 = Date()
        #expect(policy.admit(alert(), now: t0, hostingTerminalIsFrontmost: false).allowed)
        let second = policy.admit(alert(), now: t0.addingTimeInterval(5), hostingTerminalIsFrontmost: false)
        #expect(!second.allowed)
        #expect(second.reason == "doublon")
    }

    @Test("the same alert after the window gets through again")
    func dedupeExpires() {
        var policy = AlertPolicy()
        let t0 = Date()
        _ = policy.admit(alert(), now: t0, hostingTerminalIsFrontmost: false)
        let later = t0.addingTimeInterval(AlertPolicy.dedupeWindow + 1)
        #expect(policy.admit(alert(), now: later, hostingTerminalIsFrontmost: false).allowed)
    }

    // Three sessions finishing together should interrupt once, not three times.
    @Test("a burst from different sessions is rate limited")
    func rateLimit() {
        var policy = AlertPolicy()
        let t0 = Date()
        #expect(policy.admit(alert("a"), now: t0, hostingTerminalIsFrontmost: false).allowed)
        let second = policy.admit(alert("b"), now: t0.addingTimeInterval(1), hostingTerminalIsFrontmost: false)
        #expect(!second.allowed)
        #expect(second.reason == "débit limité")
    }

    @Test("the gap reopens once it has elapsed")
    func gapReopens() {
        var policy = AlertPolicy()
        let t0 = Date()
        _ = policy.admit(alert("a"), now: t0, hostingTerminalIsFrontmost: false)
        let later = t0.addingTimeInterval(AlertPolicy.minimumGap + 1)
        #expect(policy.admit(alert("b"), now: later, hostingTerminalIsFrontmost: false).allowed)
    }
}

@Suite("SessionAlert tracker")
@MainActor
struct AlertTrackerTests {

    @Test("a finished session produces one attributed alert")
    func oneAlert() {
        let bus = AlertBus()
        let tracker = AlertTracker(bus: bus)
        tracker.ingest([session("s1", action: .shell)])
        let alerts = tracker.ingest([session("s1", turnEnded: true)])
        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .finished)
        #expect(alerts.first?.projectName == "notch")
    }

    @Test("repeated snapshots of the same finished turn stay silent")
    func noRepeat() {
        let bus = AlertBus()
        let tracker = AlertTracker(bus: bus)
        tracker.ingest([session("s1", action: .shell)])
        var total = tracker.ingest([session("s1", turnEnded: true)]).count
        for _ in 0..<5 { total += tracker.ingest([session("s1", turnEnded: true)]).count }
        #expect(total == 1)
    }

    // Watching several agents at once is the point; a single "current session"
    // notion would lose all but the newest.
    @Test("three sessions keep three independent states")
    func independentStates() {
        let bus = AlertBus()
        let tracker = AlertTracker(bus: bus)
        tracker.ingest([
            session("a", project: "notch", action: .shell),
            session("b", project: "hykaro", action: .editing),
            session("c", project: "tigreboite"),
        ])
        #expect(tracker.state(of: "a") == .working)
        #expect(tracker.state(of: "b") == .working)
        #expect(tracker.state(of: "c") == .idle)
        #expect(tracker.trackedSessions == 3)
    }

    @Test("a vanished session stops being tracked")
    func forgetsVanished() {
        let bus = AlertBus()
        let tracker = AlertTracker(bus: bus)
        tracker.ingest([session("a"), session("b")])
        #expect(tracker.trackedSessions == 2)
        tracker.ingest([session("a")])
        #expect(tracker.trackedSessions == 1)
    }

    @Test("suppressed alerts are recorded rather than dropped silently")
    func suppressionIsVisible() {
        let bus = AlertBus()
        let tracker = AlertTracker(bus: bus)
        tracker.isHostingTerminalFrontmost = { _ in true }
        tracker.ingest([session("s1", action: .shell)])
        let alerts = tracker.ingest([session("s1", turnEnded: true)])
        #expect(alerts.isEmpty)
        #expect(tracker.suppressed.count == 1)
        #expect(tracker.suppressed.first?.reason == "terminal au premier plan")
    }

    @Test("the bus keeps a bounded history and feeds subscribers")
    func busHistory() {
        let bus = AlertBus()
        for i in 0..<(AlertBus.historyLimit + 10) {
            bus.publish(SessionAlert(sessionID: "s\(i)", projectName: "p", kind: .finished, at: Date()))
        }
        #expect(bus.delivered.count == AlertBus.historyLimit)
    }
}
