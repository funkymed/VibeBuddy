import Testing
import Foundation
@testable import VibeBuddyKit

private func session(
    _ id: String, project: String = "notch",
    action: ToolAction = .none, turnEnded: Bool = false,
    error: Bool = false, subagents: Int = 0, live: Bool = true
) -> AgentSession {
    AgentSession(
        id: id, cwd: "/Users/dev/\(project)", projectName: project,
        model: "claude-opus-5", startedAt: Date(), lastActivity: Date(),
        status: nil, action: action, permissionMode: "auto",
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

@Suite("Session grouping")
struct SessionGroupTests {

    private func session(
        _ id: String, cwd: String, live: Bool = true, ago: TimeInterval = 0
    ) -> AgentSession {
        AgentSession(
            id: id, cwd: cwd, projectName: (cwd as NSString).lastPathComponent,
            model: "claude-opus-5", startedAt: Date(),
            lastActivity: Date().addingTimeInterval(-ago),
            status: nil, action: .none, permissionMode: "auto",
            contextTokens: 0, contextWindow: 200_000, pid: nil, isLive: live
        )
    }

    // Five runs in one directory is an ordinary afternoon. Shown flat, the
    // session actually running is buried under its own history.
    @Test("runs in one directory collapse to one row")
    func collapsesHistory() {
        let groups = SessionGroup.group([
            session("a", cwd: "/p/notch", live: true),
            session("b", cwd: "/p/notch", live: false, ago: 600),
            session("c", cwd: "/p/notch", live: false, ago: 900),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
        #expect(groups[0].hasHistory)
    }

    // The failure that matters: a finished run must never mask a running one.
    @Test("the live session is the one shown, whatever its age")
    func livePrimaryWins() {
        let groups = SessionGroup.group([
            session("old-live", cwd: "/p/notch", live: true, ago: 3600),
            session("recent-dead", cwd: "/p/notch", live: false, ago: 10),
        ])
        #expect(groups[0].primary.id == "old-live")
        #expect(groups[0].liveCount == 1)
    }

    @Test("separate directories stay separate")
    func distinctProjects() {
        let groups = SessionGroup.group([
            session("a", cwd: "/p/notch"),
            session("b", cwd: "/p/hykaro"),
        ])
        #expect(groups.count == 2)
    }

    @Test("groups are ordered live first, then by recency")
    func ordering() {
        let groups = SessionGroup.group([
            session("dead", cwd: "/p/a", live: false, ago: 5),
            session("live", cwd: "/p/b", live: true, ago: 5000),
        ])
        #expect(groups[0].cwd == "/p/b")
    }

    @Test("a single session still forms a group, without history")
    func singleSession() {
        let groups = SessionGroup.group([session("a", cwd: "/p/notch")])
        #expect(groups.count == 1)
        #expect(!groups[0].hasHistory)
    }

    @Test("no sessions yields no groups")
    func empty() {
        #expect(SessionGroup.group([]).isEmpty)
    }
}

/// Grouping folds history, never running agents.
@Suite("Live sessions are never folded")
struct LiveGroupingTests {

    private func session(
        _ id: String, cwd: String, live: Bool, activity: Date = Date()
    ) -> AgentSession {
        AgentSession(
            id: id, cwd: cwd, projectName: (cwd as NSString).lastPathComponent,
            model: "", startedAt: activity, lastActivity: activity,
            status: nil, action: .none, permissionMode: "",
            contextTokens: 0, contextWindow: 200_000, pid: nil, isLive: live)
    }

    // Four agents in one folder used to collapse into a single row: the app
    // exists to watch several at once.
    @Test("every live session gets its own row")
    func liveSessionsAreNotFolded() {
        let rows = SessionGroup.group([
            session("a", cwd: "/p/notch", live: true),
            session("b", cwd: "/p/notch", live: true),
            session("c", cwd: "/p/notch", live: true),
        ])
        #expect(rows.count == 3)
        // Distinct ids, or `ForEach` silently drops the duplicates.
        #expect(Set(rows.map(\.id)).count == 3)
    }

    @Test("finished runs still fold into one row")
    func historyStillFolds() {
        let rows = SessionGroup.group([
            session("old1", cwd: "/p/notch", live: false),
            session("old2", cwd: "/p/notch", live: false),
            session("old3", cwd: "/p/notch", live: false),
        ])
        #expect(rows.count == 1)
        #expect(rows.first?.count == 3)
    }

    // The badge says "there is history here", once per folder rather than on
    // every sibling.
    @Test("history rides on the first live row only")
    func historyRidesOnOneRow() {
        let rows = SessionGroup.group([
            session("live1", cwd: "/p/notch", live: true, activity: Date()),
            session("live2", cwd: "/p/notch", live: true,
                    activity: Date(timeIntervalSinceNow: -60)),
            session("dead", cwd: "/p/notch", live: false,
                    activity: Date(timeIntervalSinceNow: -600)),
        ])
        #expect(rows.count == 2)
        #expect(rows.filter(\.hasHistory).count == 1)
        #expect(rows.first?.count == 2)   // itself plus the dead run
    }

    @Test("folders stay separate and live ones come first")
    func foldersStaySeparate() {
        let rows = SessionGroup.group([
            session("dead", cwd: "/p/old", live: false),
            session("live", cwd: "/p/notch", live: true),
        ])
        #expect(rows.count == 2)
        #expect(rows.first?.primary.id == "live")
    }
}

/// Cold start must not announce turns that ended before the app existed.
@Suite("First sight of a session")
@MainActor
struct FirstSightTests {

    private func finished(_ id: String) -> AgentSession {
        AgentSession(
            id: id, cwd: "/p/notch", projectName: "notch", model: "",
            startedAt: Date(), lastActivity: Date(), status: nil, action: .none,
            permissionMode: "", contextTokens: 0, contextWindow: 200_000,
            pid: 42, isLive: true, turnEnded: true)
    }

    private func working(_ id: String) -> AgentSession {
        AgentSession(
            id: id, cwd: "/p/notch", projectName: "notch", model: "",
            startedAt: Date(), lastActivity: Date(), status: nil, action: .shell,
            permissionMode: "", contextTokens: 0, contextWindow: 200_000,
            pid: 42, isLive: true)
    }

    @Test("a session already finished when first seen says nothing")
    func coldStartIsSilent() {
        let tracker = AlertTracker(bus: AlertBus())
        #expect(tracker.ingest([finished("a")]).isEmpty)
    }

    // The point of the app: a turn that ends while it watches must alert.
    @Test("a turn that ends under our eyes still alerts")
    func liveTransitionStillAlerts() {
        let tracker = AlertTracker(bus: AlertBus())
        #expect(tracker.ingest([working("a")]).isEmpty)
        let alerts = tracker.ingest([finished("a")])
        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .finished)
    }

    @Test("silence on first sight is per session, not global")
    func perSession() {
        let tracker = AlertTracker(bus: AlertBus())
        _ = tracker.ingest([working("a")])
        // "b" appears already finished: new to us, so no alert for it — while
        // "a" finishing in the same snapshot is a real transition.
        let alerts = tracker.ingest([finished("a"), finished("b")])
        #expect(alerts.map(\.sessionID) == ["a"])
    }
}
