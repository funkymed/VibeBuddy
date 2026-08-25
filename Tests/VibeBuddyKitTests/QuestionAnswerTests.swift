import Foundation
import Testing
import VibeHookProtocol
@testable import VibeBuddyKit

/// The `AskUserQuestion` hijack, T6.
@Suite("Answering a question through a deny")
@MainActor
struct QuestionAnswerTests {
    @Test("The chosen option appears verbatim in the message")
    func optionIsCarriedWhole() {
        let message = QuestionAnswer.denyMessage(for: "Deux curseurs séparés")
        #expect(message.contains("Deux curseurs séparés"))
    }

    /// The whole point of the wording.
    @Test("The message says it is an answer, not a refusal")
    func messageFramesItselfAsAnAnswer() {
        let message = QuestionAnswer.denyMessage(for: "Garder couplé")
        #expect(message.lowercased().contains("not a refusal"))
        #expect(message.lowercased().contains("continue"))
        #expect(message != "Garder couplé")
    }

    /// Guards the "fix" the doc comment warns about: an `allow` sends nothing back, so
    /// the model never learns which option was chosen.
    @Test("The decision is a deny, never an allow")
    func decisionIsADeny() {
        let decision = QuestionAnswer.decision(for: "Curseur = pastille seule")
        guard case let .deny(message) = decision else {
            Issue.record("An answer must travel as a deny — there is no other channel")
            return
        }
        #expect(message == QuestionAnswer.denyMessage(for: "Curseur = pastille seule"))
    }

    /// End to end through the queue, which is what the panel actually drives.
    @Test("A question answered from the notch comes back framed")
    func answeringThroughTheQueue() async {
        let queue = PermissionQueue()
        let payload = try! JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "tool_name": "AskUserQuestion",
            "tool_use_id": "q1",
            "session_id": "s1",
            "tool_input": ["questions": [[
                "question": "On garde le curseur couplé ?",
                "options": ["Oui", "Non"],
            ]]],
        ])
        let request = HookRequest(event: .permissionRequest, payload: payload)

        async let answer = queue.handle(request, from: nil)
        while queue.head == nil { await Task.yield() }

        #expect(queue.head?.toolName == "AskUserQuestion")
        guard case let .question(_, options)? = queue.head?.summary else {
            Issue.record("An AskUserQuestion must parse as a question")
            return
        }
        #expect(options == ["Oui", "Non"])

        queue.decide("q1", QuestionAnswer.decision(for: options[1]))

        guard case let .deny(message)?? = await answer else {
            Issue.record("The hook must be answered, and with a deny")
            return
        }
        #expect(message.contains("Non"))
        #expect(message.contains("not a refusal"))
        #expect(queue.isEmpty)
    }
}

/// What « always allow » means on a question: nothing, and it must not be offered.
@Suite("A question is never granted in advance")
@MainActor
struct QuestionIsNeverPreGrantedTests {
    private func question(id: String) -> HookRequest {
        HookRequest(event: .permissionRequest, payload: try! JSONSerialization.data(
            withJSONObject: [
                "hook_event_name": "PermissionRequest",
                "tool_name": "AskUserQuestion",
                "tool_use_id": id,
                "tool_input": ["questions": [["question": "Alors ?", "options": ["A", "B"]]]],
            ]))
    }

    @Test("A rule naming AskUserQuestion does not silence the panel")
    func ruleDoesNotShortCircuit() async {
        let queue = PermissionQueue()
        // Whatever put it there — the user's own hand, or an older build of this app
        // offering « toujours autoriser » on a question.
        queue.alwaysAllowed = { ["AskUserQuestion", "Bash"] }

        async let answer = queue.handle(question(id: "q1"), from: nil)
        while queue.head == nil { await Task.yield() }

        #expect(queue.head?.toolName == "AskUserQuestion")
        queue.decide("q1", QuestionAnswer.decision(for: "A"))
        _ = await answer
    }

    /// The same rule on a tool that really can be granted still works: the guard is
    /// about questions, not about turning the feature off.
    @Test("A bare rule still short-circuits a runnable tool")
    func ruleStillWorksElsewhere() async {
        let queue = PermissionQueue()
        queue.alwaysAllowed = { ["Bash"] }
        let request = HookRequest(event: .permissionRequest, payload: try! JSONSerialization.data(
            withJSONObject: [
                "hook_event_name": "PermissionRequest",
                "tool_name": "Bash",
                "tool_use_id": "b1",
                "tool_input": ["command": "ls"],
            ]))
        #expect(await queue.handle(request, from: nil) == .allow)
        #expect(queue.isEmpty)
    }
}
