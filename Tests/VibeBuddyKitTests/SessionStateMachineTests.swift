import Testing
import Foundation
@testable import VibeBuddyKit

private func observe(
    action: ToolAction = .none,
    turnEnded: Bool = false,
    error: Bool = false,
    subagents: Int = 0,
    live: Bool = true
) -> SessionObservation {
    SessionObservation(
        sessionID: "s1", projectName: "notch", action: action,
        turnEnded: turnEnded, lastResultWasError: error,
        subagentsRunning: subagents, isLive: live, at: Date()
    )
}

@Suite("Session state transitions")
struct SessionStateTests {

    @Test("a running tool means working")
    func toolMeansWorking() {
        let (state, alert) = SessionStateMachine.advance(from: .idle, observing: observe(action: .shell))
        #expect(state == .working)
        #expect(alert == nil)
    }

    @Test("a completed turn finishes and alerts once")
    func completionAlerts() {
        let (state, alert) = SessionStateMachine.advance(
            from: .working, observing: observe(turnEnded: true))
        #expect(state == .finished)
        #expect(alert == .finished)
    }

    @Test("a completed turn after an error reports failure")
    func errorFinishes() {
        let (state, alert) = SessionStateMachine.advance(
            from: .working, observing: observe(turnEnded: true, error: true))
        #expect(state == .failed)
        #expect(alert == .failed)
    }
}

// Every test here is about *not* firing. These are the failure modes that make
// a notification system worth turning off.
@Suite("Alerts that must not fire")
struct AlertSuppressionTests {

    // The rule the whole design rests on: an alert belongs to a transition, not
    // to a state. Re-reading the same transcript must stay silent.
    @Test("a second reading of the same finished turn is silent")
    func noRepeatOnRefresh() {
        let first = SessionStateMachine.advance(from: .working, observing: observe(turnEnded: true))
        #expect(first.alert == .finished)

        let second = SessionStateMachine.advance(from: first.state, observing: observe(turnEnded: true))
        #expect(second.state == .finished)
        #expect(second.alert == nil, "the same completed turn alerted twice")
    }

    @Test("ten refreshes of a finished session produce exactly one alert")
    func exactlyOneAlert() {
        var state = SessionActivity.working
        var alerts = 0
        for _ in 0..<10 {
            let step = SessionStateMachine.advance(from: state, observing: observe(turnEnded: true))
            state = step.state
            if step.alert != nil { alerts += 1 }
        }
        #expect(alerts == 1)
    }

    // A subagent finishing is not the turn finishing. Without this, every
    // delegation fires a notification — which is how people learn to ignore them.
    @Test("a subagent still running keeps the turn open")
    func subagentBlocksCompletion() {
        let (state, alert) = SessionStateMachine.advance(
            from: .working, observing: observe(turnEnded: true, subagents: 1))
        #expect(state == .working)
        #expect(alert == nil)
    }

    @Test("a tool still running beats a stale completion marker")
    func runningToolWins() {
        let (state, alert) = SessionStateMachine.advance(
            from: .idle, observing: observe(action: .editing, turnEnded: true))
        #expect(state == .working)
        #expect(alert == nil)
    }

    // The process is gone, so the user already knows. Alerting here would mean
    // a notification every time the app restarts and re-reads old transcripts.
    @Test("a dead session never alerts")
    func deadSessionSilent() {
        let (state, alert) = SessionStateMachine.advance(
            from: .working, observing: observe(turnEnded: true, live: false))
        #expect(state == .idle)
        #expect(alert == nil)
    }

    @Test("an idle session with nothing to say stays quiet")
    func idleStaysQuiet() {
        let (state, alert) = SessionStateMachine.advance(from: .idle, observing: observe())
        #expect(state == .idle)
        #expect(alert == nil)
    }
}

@Suite("Full turn sequences")
struct TurnSequenceTests {

    /// Run a script of observations and collect what fired.
    private func run(_ script: [SessionObservation]) -> [SessionAlert.Kind] {
        var state = SessionActivity.idle
        var fired: [SessionAlert.Kind] = []
        for observation in script {
            let step = SessionStateMachine.advance(from: state, observing: observation)
            state = step.state
            if let kind = step.alert { fired.append(kind) }
        }
        return fired
    }

    @Test("a normal turn fires once, at the end")
    func normalTurn() {
        #expect(run([
            observe(action: .reading),
            observe(action: .editing),
            observe(action: .shell),
            observe(turnEnded: true),
        ]) == [.finished])
    }

    @Test("a turn with delegation still fires once")
    func turnWithSubagents() {
        #expect(run([
            observe(action: .delegating),
            observe(subagents: 2),
            observe(subagents: 1),          // one subagent returned — not the turn
            observe(turnEnded: true),
        ]) == [.finished])
    }

    @Test("two consecutive turns fire twice")
    func twoTurns() {
        #expect(run([
            observe(action: .shell),
            observe(turnEnded: true),
            observe(action: .shell),        // user replied, work resumed
            observe(turnEnded: true),
        ]) == [.finished, .finished])
    }

    @Test("a failing turn reports failure, not completion")
    func failingTurn() {
        #expect(run([
            observe(action: .shell),
            observe(turnEnded: true, error: true),
        ]) == [.failed])
    }
}
