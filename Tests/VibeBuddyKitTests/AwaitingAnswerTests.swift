import Foundation
import Testing
@testable import VibeBuddyKit

/// A pending question, read from the transcript.
///
/// The shape is fixed and was measured, not assumed: an assistant entry carries
/// `tool_use` with an `id`, and the answer comes back as a `user` entry carrying
/// `tool_result` with a matching `tool_use_id`. Between the two, nothing is
/// written — which is exactly the window this detects.
@Suite("Awaiting an answer")
struct AwaitingAnswerTests {

    private func transcript(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    private let question = """
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use",\
    "id":"toolu_A","name":"AskUserQuestion","input":{"questions":[{"question":\
    "Garder le rendu pixelisé ?","header":"Rendu"}]}}]}}
    """

    private let answer = """
    {"type":"user","message":{"role":"user","content":[{"type":"tool_result",\
    "tool_use_id":"toolu_A","content":"Your questions have been answered"}]}}
    """

    @Test("a question with no answer behind it is a wait")
    func pendingQuestion() {
        let tail = TranscriptParser.parse(transcript([question]))
        #expect(tail.awaitingQuestion)
        #expect(tail.question == "Garder le rendu pixelisé ?")
    }

    // The scan runs newest-first, so the answer is seen before the question it
    // answers. Getting that order wrong would report every answered question as
    // still pending — an alert on every conversation.
    @Test("an answered question is not a wait")
    func answeredQuestion() {
        let tail = TranscriptParser.parse(transcript([question, answer]))
        #expect(tail.awaitingQuestion == false)
        #expect(tail.question == nil)
    }

    @Test("ExitPlanMode counts as a question")
    func planApproval() {
        let entry = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use",\
        "id":"toolu_B","name":"ExitPlanMode","input":{"plan":"1. faire ceci"}}]}}
        """
        let tail = TranscriptParser.parse(transcript([entry]))
        #expect(tail.awaitingQuestion)
    }

    // Any pending `tool_use` looks the same in the file. Only tools that *are*
    // questions may be read as a wait, or every slow command becomes one.
    @Test("a running tool is not a wait")
    func pendingToolIsNotAQuestion() {
        let entry = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use",\
        "id":"toolu_C","name":"Bash","input":{"command":"swift build"}}]}}
        """
        let tail = TranscriptParser.parse(transcript([entry]))
        #expect(tail.awaitingQuestion == false)
        #expect(tail.action == .shell)
    }

    @Test("the closed list is what decides")
    func closedList() {
        #expect(QuestionTools.asks("AskUserQuestion"))
        #expect(QuestionTools.asks("ExitPlanMode"))
        #expect(!QuestionTools.asks("Bash"))
        #expect(!QuestionTools.asks("Task"))
    }

    // MARK: - State machine

    private func observation(
        awaiting: Bool, action: ToolAction = .none, turnEnded: Bool = false
    ) -> SessionObservation {
        SessionObservation(
            sessionID: "s", projectName: "p", action: action, turnEnded: turnEnded,
            lastResultWasError: false, subagentsRunning: 0, isLive: true,
            at: Date(), awaitingAnswer: awaiting)
    }

    @Test("arriving at a question alerts once, staying there does not")
    func alertsOnceOnTransition() {
        let first = SessionStateMachine.advance(
            from: .working, observing: observation(awaiting: true))
        #expect(first.state == .awaiting)
        #expect(first.alert == .needsAttention)

        let second = SessionStateMachine.advance(
            from: .awaiting, observing: observation(awaiting: true))
        #expect(second.state == .awaiting)
        #expect(second.alert == nil)
    }

    // `ExitPlanMode` classifies as planning, so a machine that checked the
    // action first would report an agent that has been standing still since the
    // plan was printed as busy planning.
    @Test("a question outranks a classified action")
    func questionBeatsAction() {
        let step = SessionStateMachine.advance(
            from: .idle, observing: observation(awaiting: true, action: .planning))
        #expect(step.state == .awaiting)
    }

    @Test("a dead session never reports a pending question")
    func deadSessionIsSilent() {
        let dead = SessionObservation(
            sessionID: "s", projectName: "p", action: .none, turnEnded: false,
            lastResultWasError: false, subagentsRunning: 0, isLive: false,
            at: Date(), awaitingAnswer: true)
        let step = SessionStateMachine.advance(from: .awaiting, observing: dead)
        #expect(step.state == .idle)
        #expect(step.alert == nil)
    }

    @Test("waiting is worth interrupting for")
    func waitingIsNotable() {
        #expect(SessionActivity.awaiting.isNotable)
    }

    // The face existed in every buddy file and nothing ever produced it. This is
    // what now does.
    @Test("the awaiting face finally has a producer")
    func buddyShowsTheFace() {
        let expression = BuddyExpression.from(
            activity: .awaiting, hasLiveSession: true, isVisible: true)
        #expect(expression == .awaiting)
    }
}
