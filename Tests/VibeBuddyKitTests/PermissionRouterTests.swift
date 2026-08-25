import Testing
import Foundation
import VibeHookProtocol
@testable import VibeBuddyKit

/// The routing behind the permission panel, exercised without a window.
///
/// Every one of these encodes a defect that was found by hand on 2026-08-21:
/// a request answered twice, a consent left standing over a request that had
/// gone, an allow that reached Claude Code before the rule was on disk.
@Suite("Permission router")
@MainActor
struct PermissionRouterTests {

    // MARK: - The guard

    @Test("The same request at the same count changes nothing")
    func sameIDSameWaitingIsInert() {
        let router = PermissionRouter()
        let model = PermissionSamples.model("shell")

        _ = router.set(model, waiting: 0)
        let again = router.set(model, waiting: 0)

        #expect(!again.changed)
        // Nothing to remeasure, so nothing to swap either.
        #expect(!again.wasShowingSomething)
        #expect(again.hasRequest)
    }

    /// The counter is part of what is on screen: « +2 en attente » becoming
    /// « +1 » is a change the panel has to redraw and remeasure.
    @Test("The same request at a different count does change")
    func sameIDDifferentWaitingChanges() {
        let router = PermissionRouter()
        let model = PermissionSamples.model("shell")

        _ = router.set(model, waiting: 2)
        let verdict = router.set(model, waiting: 1)

        #expect(verdict.changed)
        #expect(verdict.hasRequest)
        #expect(router.waiting == 1)
    }

    /// The guard compares identifiers, never models. Two models sharing an id
    /// are the same request; replaying the sequence for them buys an off-screen
    /// layout and an animation for nothing.
    @Test("Two different bodies under one id are the same request")
    func theGuardComparesIdentifiers() {
        let router = PermissionRouter()
        let questions = PermissionSamples.questions(2)
        let first = questions[0]
        let twin = PermissionRequestModel(
            id: first.id, toolName: first.toolName, sessionID: first.sessionID,
            cwd: first.cwd, summary: questions[1].summary,
            suggestions: [], receivedAt: first.receivedAt)

        _ = router.set(first, waiting: 0)
        #expect(twin != first)
        #expect(!router.set(twin, waiting: 0).changed)
    }

    // MARK: - Opening, swapping, closing

    @Test("The very first request is not a swap")
    func firstRequestIsNotASwap() {
        let router = PermissionRouter()

        let verdict = router.set(PermissionSamples.model("shell"), waiting: 0)

        #expect(verdict.changed)
        #expect(verdict.hasRequest)
        // Nothing was on screen: the panel opens rather than swapping.
        #expect(!verdict.wasShowingSomething)
    }

    @Test("A second request over the first is a swap")
    func secondRequestIsASwap() {
        let router = PermissionRouter()
        let questions = PermissionSamples.questions(2)

        _ = router.set(questions[0], waiting: 1)
        let verdict = router.set(questions[1], waiting: 0)

        #expect(verdict.changed)
        #expect(verdict.hasRequest)
        #expect(verdict.wasShowingSomething)
    }

    /// When the last one goes the panel returns to the pill, and only because
    /// something *was* there: a `nil` on an empty router leaves it alone.
    @Test("Taking the last request away is a withdrawal")
    func withdrawalIsFlagged() {
        let router = PermissionRouter()
        _ = router.set(PermissionSamples.model("shell"), waiting: 0)

        let verdict = router.set(nil, waiting: 0)

        #expect(verdict.changed)
        #expect(!verdict.hasRequest)
        #expect(verdict.wasShowingSomething)
        #expect(router.permission == nil)
    }

    // MARK: - Consent

    /// The request went away under the consent screen — expired, or answered in
    /// the terminal. There is nothing left to grant.
    @Test("A consent dies with the request it was built for")
    func consentDiesWithItsRequest() {
        let router = PermissionRouter()
        let model = PermissionSamples.model("shell")
        router.onAlwaysAllowAsked = { Self.consent(for: $0) }

        _ = router.set(model, waiting: 0)
        #expect(router.alwaysAllow())
        #expect(router.consent != nil)

        let verdict = router.set(nil, waiting: 0)

        #expect(router.consent == nil)
        // Still a swap out of something, even though the request had gone
        // first: the consent screen was what the user was looking at.
        #expect(verdict.wasShowingSomething)
    }

    /// When there is nothing to write — the rule is already granted — it is
    /// simply an allow, with no screen in the way.
    @Test("Nothing to write means a plain allow and no screen")
    func alwaysAllowWithNothingToWriteIsAnAllow() {
        let router = PermissionRouter()
        var decisions: [(String, HookDecision?)] = []
        router.onDecision = { decisions.append(($0, $1)) }
        router.onAlwaysAllowAsked = { _ in nil }

        let model = PermissionSamples.model("shell")
        _ = router.set(model, waiting: 0)

        #expect(!router.alwaysAllow())
        #expect(router.consent == nil)
        #expect(decisions.count == 1)
        #expect(decisions.first?.0 == model.id)
        #expect(decisions.first?.1 == .allow)
    }

    @Test("With no request at all, « toujours autoriser » answers nobody")
    func alwaysAllowWithoutARequestIsSilent() {
        let router = PermissionRouter()
        var decisions = 0
        router.onDecision = { _, _ in decisions += 1 }
        router.onAlwaysAllowAsked = { Self.consent(for: $0) }

        #expect(!router.alwaysAllow())
        #expect(decisions == 0)
    }

    /// The socket stays open on purpose here: the screen is up, the user has
    /// not decided yet, and answering now would grant what they are reading.
    @Test("A consent to show answers nothing yet")
    func alwaysAllowWithAConsentAnswersNothing() {
        let router = PermissionRouter()
        var decisions = 0
        router.onDecision = { _, _ in decisions += 1 }
        router.onAlwaysAllowAsked = { Self.consent(for: $0) }

        _ = router.set(PermissionSamples.model("shell"), waiting: 0)

        #expect(router.alwaysAllow())
        #expect(router.consent != nil)
        #expect(decisions == 0)
    }

    @Test("Cancelling a consent leaves the request standing")
    func cancelKeepsTheRequest() {
        let router = PermissionRouter()
        var decisions = 0
        router.onDecision = { _, _ in decisions += 1 }
        router.onAlwaysAllowAsked = { Self.consent(for: $0) }

        let model = PermissionSamples.model("shell")
        _ = router.set(model, waiting: 0)
        _ = router.alwaysAllow()
        router.cancelConsent()

        #expect(router.consent == nil)
        #expect(router.permission?.id == model.id)
        // Cancelling is not a decision: the request is still waiting.
        #expect(decisions == 0)
    }

    /// The invariant: an allow that reached Claude Code before the rule was on
    /// disk would be granted once and asked again next time, which reads as the
    /// button not working.
    @Test("Confirming writes the rule before it answers")
    func confirmWritesBeforeAnswering() {
        let router = PermissionRouter()
        var order: [String] = []
        router.onDecision = { _, _ in order.append("answer") }
        router.onConsentConfirmed = { _ in order.append("write") }
        router.onAlwaysAllowAsked = { Self.consent(for: $0) }

        _ = router.set(PermissionSamples.model("shell"), waiting: 0)
        _ = router.alwaysAllow()
        router.confirmConsent()

        #expect(order == ["write", "answer"])
        #expect(router.consent == nil)
    }

    @Test("Confirming nothing writes nothing and answers nobody")
    func confirmWithoutAConsentIsSilent() {
        let router = PermissionRouter()
        var events = 0
        router.onDecision = { _, _ in events += 1 }
        router.onConsentConfirmed = { _ in events += 1 }

        _ = router.set(PermissionSamples.model("shell"), waiting: 0)
        router.confirmConsent()

        #expect(events == 0)
    }

    // MARK: - Answering

    @Test("Answering with no request on screen reaches nobody")
    func answerWithoutARequestIsSilent() {
        let router = PermissionRouter()
        var decisions = 0
        router.onDecision = { _, _ in decisions += 1 }

        router.answer(.allow)
        _ = router.set(PermissionSamples.model("shell"), waiting: 0)
        _ = router.set(nil, waiting: 0)
        router.answer(.allow)

        #expect(decisions == 0)
    }

    /// A chosen option travels as a deny whose reason is the answer. The router
    /// carries the decision it is given and never normalises it — anyone who
    /// "fixes" this into an allow breaks every question answered from the notch.
    @Test("An answered question travels as the deny it is")
    func questionAnswerIsPassedThroughUntouched() {
        let router = PermissionRouter()
        var decisions: [(String, HookDecision?)] = []
        router.onDecision = { decisions.append(($0, $1)) }

        let model = PermissionSamples.questions(1)[0]
        _ = router.set(model, waiting: 0)
        router.answer(QuestionAnswer.decision(for: "Oui"))

        #expect(decisions.count == 1)
        #expect(decisions.first?.0 == model.id)
        guard case let .deny(message)? = decisions.first?.1 else {
            Issue.record("attendu un deny, reçu \(String(describing: decisions.first?.1))")
            return
        }
        #expect(message == QuestionAnswer.denyMessage(for: "Oui"))
    }

    // MARK: - isHoldingAnAsk

    @Test("A fresh router holds nothing")
    func freshRouterHoldsNothing() {
        #expect(!PermissionRouter().isHoldingAnAsk)
    }

    @Test("A request on screen is an ask")
    func aRequestIsAnAsk() {
        let router = PermissionRouter()
        _ = router.set(PermissionSamples.model("question"), waiting: 0)
        #expect(router.isHoldingAnAsk)
    }

    /// The consent screen is an ask in its own right: the request behind it is
    /// still pending, and the panel must not close under the diff either.
    @Test("A consent alone is still an ask")
    func aConsentIsAnAsk() {
        let router = PermissionRouter()
        router.onAlwaysAllowAsked = { Self.consent(for: $0) }
        _ = router.set(PermissionSamples.model("shell"), waiting: 0)
        _ = router.alwaysAllow()

        #expect(router.isHoldingAnAsk)
        // And it stops being one only once it is answered.
        router.confirmConsent()
        _ = router.set(nil, waiting: 0)
        #expect(!router.isHoldingAnAsk)
    }

    // MARK: - Helpers

    private static func consent(for model: PermissionRequestModel) -> PermissionConsent {
        PermissionConsent(
            requestID: model.id, rule: "Bash(git status:*)",
            diff: "+ Bash(git status:*)", backupDirectory: "/tmp")
    }
}
