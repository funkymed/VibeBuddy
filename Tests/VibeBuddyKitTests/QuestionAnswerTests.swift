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
        guard case let .question(questions)? = queue.head?.summary,
              let options = questions.first?.options else {
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

    // One question, one pick: the same message as before, so nothing the model has
    // already learnt to read changes.
    @Test("A single pick keeps the single-answer wording")
    func singlePickUnchanged() {
        #expect(QuestionAnswer.denyMessage(for: [("Laquelle ?", ["Oui"])])
            == QuestionAnswer.denyMessage(for: "Oui"))
    }

    @Test("Every question is named with all of its picks")
    func severalPicks() {
        let message = QuestionAnswer.denyMessage(for: [
            ("Quels scénarios ?", ["A — repos", "C — panneau ouvert"]),
            ("Combien de manches ?", ["Trois"]),
        ])
        #expect(message.contains("\"Quels scénarios ?\" → \"A — repos\", \"C — panneau ouvert\""))
        #expect(message.contains("\"Combien de manches ?\" → \"Trois\""))
        #expect(message.lowercased().contains("not a refusal"))
        guard case .deny = QuestionAnswer.decision(for: [("q", ["a", "b"])]) else {
            Issue.record("attendu un deny"); return
        }
    }

    private static let input = Data(#"""
    {"questions":[
      {"question":"Quels scénarios ?","multiSelect":true,"options":[{"label":"A"},{"label":"B"},{"label":"C"}]},
      {"question":"Combien de manches ?","multiSelect":false,"options":[{"label":"Une"},{"label":"Trois"}]}
    ]}
    """#.utf8)

    // A deny reads as « Error » in the terminal and fails the turn: with the input in
    // hand, the answer goes back as the tool's own `answers`.
    @Test("With the input, the answer is an allow carrying answers")
    func answersGoBackAsInput() throws {
        let decision = QuestionAnswer.decision(
            for: [("Quels scénarios ?", ["A", "C"]), ("Combien de manches ?", ["Trois"])],
            input: Self.input)
        guard case let .allowUpdating(data) = decision else {
            Issue.record("attendu allowUpdating, reçu \(decision)"); return
        }
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let answers = try #require(object["answers"] as? [String: String])
        #expect(answers == ["Quels scénarios ?": "A, C", "Combien de manches ?": "Trois"])
        // The questions go back untouched: Claude Code validates the whole input.
        #expect((object["questions"] as? [Any])?.count == 2)
    }

    // The panel truncates long prompts; the answer must be keyed on what Claude wrote.
    @Test("Answers are keyed on the original question text, not the panel's copy")
    func keyedOnOriginalText() throws {
        let long = String(repeating: "x", count: 900)
        let input = try JSONSerialization.data(withJSONObject: [
            "questions": [["question": long, "options": [["label": "Oui"]]]],
        ])
        guard case let .allowUpdating(data) = QuestionAnswer.decision(
                for: [("xxx… (tronqué)", ["Oui"])], input: input) else {
            Issue.record("attendu allowUpdating"); return
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((object?["answers"] as? [String: String])?[long] == "Oui")
    }

    @Test("Without the input, the answer falls back to the deny")
    func fallsBackToDeny() {
        let decision = QuestionAnswer.decision(for: [("Laquelle ?", ["Oui"])], input: nil)
        #expect(decision == .deny(message: QuestionAnswer.denyMessage(for: "Oui")))
    }
}
