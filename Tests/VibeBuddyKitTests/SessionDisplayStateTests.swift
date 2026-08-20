import Testing
import Foundation
@testable import VibeBuddyKit

private func session(
    _ id: String = "s1",
    action: ToolAction = .none,
    turnEnded: Bool = false,
    error: Bool = false,
    subagents: Int = 0,
    awaiting: Bool = false,
    live: Bool = true
) -> AgentSession {
    AgentSession(
        id: id, cwd: "/Users/dev/notch", projectName: "notch",
        model: "claude-opus-5", startedAt: Date(), lastActivity: Date(),
        status: nil, action: action, permissionMode: "auto",
        contextTokens: 1000, contextWindow: 200_000, pid: 1234, isLive: live,
        turnEnded: turnEnded, lastResultWasError: error,
        subagentsRunning: subagents, awaitingAnswer: awaiting
    )
}

@Suite("Session display state")
struct SessionDisplayStateTests {

    @Test("a question outranks an error and a running tool")
    func questionWins() {
        let s = session(action: .shell, error: true, awaiting: true)
        #expect(SessionDisplayState.of(s) == .awaiting)
    }

    @Test("an error outranks a running tool")
    func errorBeatsTool() {
        #expect(SessionDisplayState.of(session(action: .shell, error: true)) == .failed)
    }

    @Test("a running tool outranks a finished turn")
    func toolBeatsTurnEnd() {
        #expect(SessionDisplayState.of(session(action: .editing, turnEnded: true)) == .working)
    }

    @Test("a subagent in flight is working, not idle")
    func subagentIsWorking() {
        #expect(SessionDisplayState.of(session(subagents: 1)) == .working)
        #expect(SessionDisplayState.of(session(turnEnded: true, subagents: 2)) == .working)
    }

    @Test("a finished turn with no tool is finished")
    func turnEnd() {
        #expect(SessionDisplayState.of(session(turnEnded: true)) == .finished)
    }

    @Test("a live session with nothing in flight is idle")
    func idle() {
        #expect(SessionDisplayState.of(session()) == .idle)
    }

    @Test("a dead session is ended whatever it carries")
    func deadIsEnded() {
        let s = session(action: .shell, turnEnded: true, error: true,
                        subagents: 3, awaiting: true, live: false)
        #expect(SessionDisplayState.of(s) == .ended)
    }

    @Test("aggregate is nil without a live session")
    func aggregateEmpty() {
        #expect(SessionDisplayState.aggregate(of: []) == nil)
        #expect(SessionDisplayState.aggregate(of: [session(live: false), session("s2", live: false)]) == nil)
    }

    @Test("aggregate keeps the most urgent live state")
    func aggregateUrgency() {
        let sessions = [
            session("s1", turnEnded: true),
            session("s2", action: .shell),
            session("s3", turnEnded: true, error: true),
        ]
        #expect(SessionDisplayState.aggregate(of: sessions) == .failed)
        #expect(SessionDisplayState.aggregate(of: sessions + [session("s4", awaiting: true)]) == .awaiting)
        #expect(SessionDisplayState.aggregate(of: [session("s1"), session("s2", action: .shell)]) == .working)
    }

    @Test("a dead session never wins the aggregate")
    func aggregateIgnoresDead() {
        let sessions = [session("s1", awaiting: true, live: false), session("s2")]
        #expect(SessionDisplayState.aggregate(of: sessions) == .idle)
    }

    @Test("the activity bridge matches the old vocabulary")
    func activityBridge() {
        #expect(SessionDisplayState.ended.activity == nil)
        #expect(SessionDisplayState.awaiting.activity == .awaiting)
        #expect(SessionDisplayState.failed.activity == .failed)
        #expect(SessionDisplayState.working.activity == .working)
        #expect(SessionDisplayState.finished.activity == .finished)
        #expect(SessionDisplayState.idle.activity == .idle)
    }
}
