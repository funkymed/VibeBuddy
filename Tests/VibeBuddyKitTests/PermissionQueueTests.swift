import Foundation
import Testing
import VibeHookProtocol
@testable import VibeBuddyKit

@Suite("The permission queue")
@MainActor
struct PermissionQueueTests {
    static func request(tool: String = "Bash", id: String,
                        command: String = "ls") -> HookRequest {
        HookRequest(
            event: .permissionRequest,
            payload: try! JSONSerialization.data(withJSONObject: [
                "hook_event_name": "PermissionRequest",
                "session_id": "s-1",
                "tool_use_id": id,
                "tool_name": tool,
                "tool_input": ["command": command],
            ]))
    }

    /// Puts a request in flight and hands back the task waiting on the answer.
    static func ask(_ queue: PermissionQueue, id: String, tool: String = "Bash")
        -> Task<HookDecision?, Never> {
        let request = request(tool: tool, id: id)
        return Task { await queue.handle(request, from: nil) }
    }

    /// Lets the enqueueing task reach its continuation.
    static func settle() async {
        for _ in 0..<4 { await Task.yield() }
    }

    // One "pending" slot made every new request silently deny the one before it, and
    // only the last survived.
    @Test("two requests in flight both survive, and answer independently")
    func parallelRequestsBothSurvive() async {
        let queue = PermissionQueue()
        let first = Self.ask(queue, id: "a")
        let second = Self.ask(queue, id: "b")
        await Self.settle()

        #expect(queue.count == 2)
        #expect(queue.head?.id == "a")
        #expect(queue.waiting == 1)

        // Answered out of order, on purpose.
        queue.deny("b", message: "non")
        queue.allow("a")

        #expect(await first.value == .allow)
        #expect(await second.value == .deny(message: "non"))
        #expect(queue.isEmpty)
    }

    @Test("the head is the oldest, and the next one takes its place")
    func fifo() async {
        let queue = PermissionQueue()
        _ = Self.ask(queue, id: "a")
        _ = Self.ask(queue, id: "b")
        _ = Self.ask(queue, id: "c")
        await Self.settle()

        #expect(queue.head?.id == "a")
        queue.allow("a")
        #expect(queue.head?.id == "b")
        #expect(queue.waiting == 1)
        queue.drain()
    }

    @Test("a decision reaches the hook that asked")
    func decisionIsDelivered() async {
        let queue = PermissionQueue()
        let asked = Self.ask(queue, id: "a")
        await Self.settle()
        queue.allow("a")
        #expect(await asked.value == .allow)
    }

    // `resume` twice traps, and the second caller is usually a stale panel.
    @Test("answering twice is harmless")
    func doubleAnswerIsIgnored() async {
        let queue = PermissionQueue()
        let asked = Self.ask(queue, id: "a")
        await Self.settle()
        queue.allow("a")
        queue.deny("a", message: "trop tard")
        queue.expire("a")
        #expect(await asked.value == .allow)
        #expect(queue.isEmpty)
    }

    @Test("an id nobody knows is ignored rather than fatal")
    func unknownIdIsIgnored() async {
        let queue = PermissionQueue()
        queue.allow("jamais-vu")
        queue.expire("jamais-vu")
        #expect(queue.isEmpty)
    }

    // Expiry means "no opinion": Claude Code shows its own prompt, which is the right
    // outcome for a request the user answered in the terminal.
    @Test("an expired request answers nothing at all")
    func expiryAnswersNil() async {
        let queue = PermissionQueue()
        let asked = Self.ask(queue, id: "a")
        await Self.settle()
        queue.expire("a")
        #expect(await asked.value == nil)
    }

    // A queue that dies holding continuations is a Claude Code that waits out its 120 s
    // timeout, once per request.
    @Test("draining answers everything, so nothing is left waiting")
    func drainAnswersEverything() async {
        let queue = PermissionQueue()
        let first = Self.ask(queue, id: "a")
        let second = Self.ask(queue, id: "b")
        await Self.settle()

        queue.drain()
        #expect(await first.value == nil)
        #expect(await second.value == nil)
        #expect(queue.isEmpty)
    }

    @Test("a rule already granted never reaches the queue")
    func alwaysAllowShortCircuits() async {
        let queue = PermissionQueue()
        queue.alwaysAllowed = { ["Bash"] }
        let decision = await queue.handle(Self.request(id: "a"), from: nil)
        #expect(decision == .allow)
        // And no panel was ever put on screen for it.
        #expect(queue.isEmpty)
    }

    // Claude Code's matcher has already run by the time a request reaches us: a scoped
    // rule that matched would never have asked.
    @Test("a scoped rule is left to Claude Code's own matcher")
    func scopedRulesAreIgnored() async {
        let queue = PermissionQueue()
        queue.alwaysAllowed = { ["Bash(npm install:*)"] }
        let asked = Self.ask(queue, id: "a")
        await Self.settle()
        #expect(queue.count == 1, "la règle scopée aurait dû être ignorée")
        queue.drain()
        _ = await asked.value
    }

    @Test("a granted rule for another tool does not grant this one")
    func rulesDoNotLeakBetweenTools() async {
        let queue = PermissionQueue()
        queue.alwaysAllowed = { ["Read"] }
        let asked = Self.ask(queue, id: "a", tool: "Bash")
        await Self.settle()
        #expect(queue.count == 1)
        queue.drain()
        _ = await asked.value
    }

    @Test("an event nobody claimed leaves Claude Code as it found it")
    func otherEventsAreNotQueued() async {
        let queue = PermissionQueue()
        let stop = HookRequest(
            event: .stop,
            payload: try! JSONSerialization.data(withJSONObject: [
                "hook_event_name": "Stop", "session_id": "s-1",
            ]))
        #expect(await queue.handle(stop, from: nil) == nil)
        #expect(queue.isEmpty)
    }

    @Test("a payload that will not parse is answered, not swallowed")
    func rubbishIsAnswered() async {
        let queue = PermissionQueue()
        let broken = HookRequest(event: .permissionRequest, payload: Data("[]".utf8))
        #expect(await queue.handle(broken, from: nil) == nil)
        #expect(queue.isEmpty)
    }

    // The server cancels the task when the peer hangs up — the user answered in the
    // terminal.
    @Test("a cancelled request answers, rather than hanging for ever")
    func cancellationAnswers() async {
        let queue = PermissionQueue()
        let asked = Self.ask(queue, id: "a")
        await Self.settle()
        #expect(queue.count == 1)

        asked.cancel()
        let answer = await asked.value
        #expect(answer == nil)
        // And the panel does not keep showing a request nobody is waiting on.
        await Self.settle()
        #expect(queue.isEmpty)
    }
}

/// The three ways a request stops being worth asking about.
@Suite("Letting a permission go")
@MainActor
struct PermissionExpiryTests {
    static let start = Date(timeIntervalSinceReferenceDate: 0)

    static func model(id: String = "a", session: String? = "s-1",
                      at when: Date = start) -> PermissionRequestModel {
        PermissionRequestModel(
            id: id, toolName: "Bash", sessionID: session, cwd: "/w",
            summary: .shell(command: "ls", description: nil), receivedAt: when)
    }

    // The tool call is written to the transcript *before* the permission is asked, so
    // an entry after it belongs to whatever happened next.
    @Test("a transcript written to after the grace period has overtaken the request")
    func staleAfterActivity() {
        let request = Self.model()
        let after = Self.start.addingTimeInterval(PermissionExpiry.staleAfter + 0.5)
        #expect(PermissionExpiry.isStale(request, lastActivity: after))
    }

    @Test("activity inside the grace period is the request's own")
    func freshWithinGrace() {
        let request = Self.model()
        let during = Self.start.addingTimeInterval(PermissionExpiry.staleAfter - 0.5)
        #expect(!PermissionExpiry.isStale(request, lastActivity: during))
        // And activity from before it was asked never counts.
        #expect(!PermissionExpiry.isStale(
            request, lastActivity: Self.start.addingTimeInterval(-10)))
    }

    @Test("a session that has said nothing at all keeps its request alive")
    func noActivityKeepsIt() {
        #expect(!PermissionExpiry.isStale(Self.model(), lastActivity: nil))
    }

    @Test("expiring for staleness answers the hook rather than dropping it")
    func staleRequestsAreAnswered() async {
        let queue = PermissionQueue()
        let asked = PermissionQueueTests.ask(queue, id: "a")
        await PermissionQueueTests.settle()

        let late = Date().addingTimeInterval(PermissionExpiry.staleAfter + 1)
        queue.expireStale { _ in late }
        #expect(await asked.value == nil)
        #expect(queue.isEmpty)
    }

    @Test("only the overtaken one goes")
    func expiryIsSelective() async {
        let queue = PermissionQueue()
        let first = PermissionQueueTests.ask(queue, id: "a")
        let second = PermissionQueueTests.ask(queue, id: "b")
        await PermissionQueueTests.settle()

        let late = Date().addingTimeInterval(PermissionExpiry.staleAfter + 1)
        queue.expireStale { $0.id == "a" ? late : nil }
        #expect(await first.value == nil)
        #expect(queue.count == 1)
        #expect(queue.head?.id == "b")
        queue.drain()
        _ = await second.value
    }

    // A panel over the window the user is looking at is a second prompt for one
    // question.
    @Test("a request whose own terminal is in front is let go")
    func frontmostHostExpires() async {
        let queue = PermissionQueue()
        let asked = PermissionQueueTests.ask(queue, id: "a")
        await PermissionQueueTests.settle()

        queue.expireIfHostIsFrontmost { _ in true }
        #expect(await asked.value == nil)
        #expect(queue.isEmpty)
    }

    @Test("a terminal that is not this request's own changes nothing")
    func otherTerminalsDoNotExpire() async {
        let queue = PermissionQueue()
        let asked = PermissionQueueTests.ask(queue, id: "a")
        await PermissionQueueTests.settle()

        queue.expireIfHostIsFrontmost { _ in false }
        #expect(queue.count == 1)
        queue.drain()
        _ = await asked.value
    }

    @Test("walking the queue while it empties itself does not lose anyone")
    func expiringEverythingIsSafe() async {
        let queue = PermissionQueue()
        let tasks = (0..<5).map { PermissionQueueTests.ask(queue, id: "r\($0)") }
        await PermissionQueueTests.settle()
        #expect(queue.count == 5)

        queue.expireIfHostIsFrontmost { _ in true }
        for task in tasks { #expect(await task.value == nil) }
        #expect(queue.isEmpty)
    }
}

/// The fixtures `--simulate-permission` shows, and the tests share.
@Suite("Rehearsal requests")
@MainActor
struct PermissionSampleTests {
    // A sample that has drifted from what the parser produces is a rehearsal of the
    // wrong play, so every kind must land on the case it claims.
    @Test("every kind produces the summary it is named for", arguments: PermissionSamples.kinds)
    func kindsMatchTheirSummary(_ kind: String) {
        let model = PermissionSamples.model(kind)
        let matches: Bool
        switch (kind, model.summary) {
        case ("shell", .shell), ("diff", .diff), ("write", .write), ("read", .read),
             ("url", .url), ("question", .question), ("plan", .question),
             ("other", .other):
            matches = true
        default:
            matches = false
        }
        #expect(matches, "\(kind) a rendu \(model.summary)")
        #expect(!model.toolName.isEmpty)
    }

    /// What separates the two `.question` samples, and the only thing that makes `plan`
    /// worth its own kind: `AskQuestionView` draws options when there are any and the
    /// plan alone when there are none, at a taller ceiling.
    @Test("the plan sample is a question with no options")
    func planHasNoOptions() {
        let model = PermissionSamples.model("plan")
        #expect(model.toolName == "ExitPlanMode")
        guard case let .question(prompt, options) = model.summary else {
            Issue.record("attendu .question, reçu \(model.summary)"); return
        }
        #expect(options.isEmpty)
        // Tall enough to pass the 260 pt ceiling, which is the point of it.
        #expect(prompt.count > 400)
    }

    /// The one thing a queue of samples must get right.
    @Test("a queue of questions has distinct ids and uneven lengths",
          arguments: [1, 3, 6])
    func questionQueueIsUsable(_ count: Int) {
        let models = PermissionSamples.questions(count)
        #expect(models.count == count)
        #expect(Set(models.map(\.id)).count == count)
        for model in models {
            #expect(model.toolName == "AskUserQuestion")
            guard case let .question(prompt, options) = model.summary else {
                Issue.record("attendu .question"); return
            }
            #expect(!prompt.isEmpty)
            #expect(!options.isEmpty)
        }
        // Three questions of the same height would prove the panel keeps its size, not
        // that it follows what it shows.
        if count >= 3 {
            #expect(Set(models.map(\.summary.promptLength)).count > 1)
        }
    }

    /// Catches a whole family of mistakes at once, and one that shipped: a multi-line
    /// literal whose continuations were flattened by the tool that wrote the file left
    /// thirteen spaces in the middle of every sentence, and the panel rendered them
    /// faithfully.
    @Test("no sample text carries stray runs of spaces",
          arguments: PermissionSamples.kinds)
    func samplesHaveNoDoubleSpaces(_ kind: String) {
        check(PermissionSamples.model(kind).summary, in: kind)
        for model in PermissionSamples.questions(4) {
            check(model.summary, in: "questions")
        }
    }

    private func check(_ summary: PermissionRequestModel.Summary, in kind: String) {
        var texts: [String] = []
        switch summary {
        case let .shell(command, description): texts = [command, description ?? ""]
        case let .question(prompt, options): texts = [prompt] + options
        case let .diff(path, _, _), let .write(path, _), let .read(path): texts = [path]
        case let .url(url): texts = [url]
        case let .other(fields): texts = fields.map(\.value)
        }
        for text in texts where text.contains("  ") {
            Issue.record("\(kind) : « \(text.prefix(80)) » contient des espaces multiples")
        }
    }

    @Test("an unknown kind falls back rather than failing")
    func unknownKindFallsBack() {
        guard case .shell = PermissionSamples.model("n'importe quoi").summary else {
            Issue.record("attendu un repli sur .shell"); return
        }
    }

    // Answering a rehearsal decides nothing: there is no hook at the other end.
    @Test("a preview goes in the queue and comes out without answering anyone")
    func previewsAnswerNobody() {
        let queue = PermissionQueue()
        var changes = 0
        queue.onChange = { changes += 1 }

        queue.insertPreview(PermissionSamples.model("question"))
        #expect(queue.head?.id == "sim-question")
        #expect(changes == 1)

        queue.allow("sim-question")
        #expect(queue.isEmpty)
        #expect(changes == 2)
    }

    // The panel is pushed to, not polled: it has to hear about both edges.
    @Test("the callback fires when a request arrives and when it leaves")
    func callbackFiresOnBothEdges() async {
        let queue = PermissionQueue()
        var seen: [String?] = []
        queue.onChange = { seen.append(queue.head?.id) }

        let asked = PermissionQueueTests.ask(queue, id: "a")
        await PermissionQueueTests.settle()
        queue.allow("a")
        _ = await asked.value

        #expect(seen == ["a", nil])
    }
}

/// The invariant Q3 of calls the most important one: every request that goes in holds a
/// socket open, and every one of them must come back out.
@Suite("The queue holds nothing open")
@MainActor
struct PermissionLifecycleTests {
    // The descriptor count that used to live here was measured process-wide, while the
    // rest of the suite ran in parallel: it counted other tests opening and closing
    // files and failed at −2.
    @Test("twenty requests in and out leave nothing behind")
    func noRequestIsLeftHolding() async {
        let queue = PermissionQueue()
        for index in 0..<20 {
            let asked = PermissionQueueTests.ask(queue, id: "r\(index)")
            await PermissionQueueTests.settle()
            switch index % 4 {
            case 0: queue.allow("r\(index)")
            case 1: queue.deny("r\(index)", message: "non")
            case 2: queue.expire("r\(index)")
            default: queue.drain()
            }
            // `value` returning is the proof the hook was answered: an unresumed
            // continuation would hang here for ever.
            _ = await asked.value
        }
        #expect(queue.isEmpty)
    }

    // Every request must be answered exactly once, whichever exit it takes: a
    // continuation resumed twice traps, and one never resumed is a Claude Code that
    // waits out its 120 s timeout.
    @Test("every exit answers, and none answers twice")
    func everyExitAnswersOnce() async {
        for exit in ["allow", "deny", "expire", "drain", "cancel"] {
            let queue = PermissionQueue()
            let asked = PermissionQueueTests.ask(queue, id: "a")
            await PermissionQueueTests.settle()

            switch exit {
            case "allow": queue.allow("a")
            case "deny": queue.deny("a", message: "non")
            case "expire": queue.expire("a")
            case "drain": queue.drain()
            default: asked.cancel()
            }
            // Answered — and the second call, which a stale panel would make, changes
            // nothing.
            _ = await asked.value
            queue.allow("a")
            await PermissionQueueTests.settle()
            #expect(queue.isEmpty, "sortie « \(exit) » a laissé la file pleine")
        }
    }
}

/// Which session a request belongs to, and what happens when we cannot tell. Measured on
/// 2026-08-21 against a running app: a permission asked in a folder where another
/// session was working died in 3,6 s, because the fallback matched any session sharing
/// the `cwd`.
@Suite("Whose activity is it")
@MainActor
struct PermissionOwnershipTests {
    static let start = Date(timeIntervalSinceReferenceDate: 0)
    /// Late enough to expire anything it is compared against.
    static let late = start.addingTimeInterval(PermissionExpiry.staleAfter + 1)

    static func model(session: String?, cwd: String? = "/w") -> PermissionRequestModel {
        PermissionRequestModel(
            id: "a", toolName: "Bash", sessionID: session, cwd: cwd,
            summary: .shell(command: "ls", description: nil), receivedAt: start)
    }

    /// The rule `HookService` applies, kept here as a value so it can be tested without
    /// an app: session id first, no fallback when it is unknown, `cwd` only when a
    /// single session can be meant.
    static func activity(
        for model: PermissionRequestModel, sessions: [(id: String, cwd: String, at: Date)]
    ) -> Date? {
        if let id = model.sessionID {
            return sessions.first { $0.id == id }?.at
        }
        guard let cwd = model.cwd else { return nil }
        let candidates = sessions.filter { $0.cwd == cwd }
        return candidates.count == 1 ? candidates[0].at : nil
    }

    @Test("a session's own activity expires its own request")
    func ownActivityExpires() {
        let request = Self.model(session: "s-1")
        let found = Self.activity(for: request, sessions: [("s-1", "/w", Self.late)])
        #expect(PermissionExpiry.isStale(request, lastActivity: found))
    }

    // The measured bug.
    @Test("a neighbour working in the same folder does not expire it")
    func neighbourDoesNotExpire() {
        let request = Self.model(session: "s-1")
        let found = Self.activity(for: request, sessions: [("s-2", "/w", Self.late)])
        #expect(found == nil)
        #expect(!PermissionExpiry.isStale(request, lastActivity: found))
    }

    @Test("with no session id, one session in the folder may speak for it")
    func singleSessionSpeaksForTheFolder() {
        let request = Self.model(session: nil)
        let found = Self.activity(for: request, sessions: [("s-2", "/w", Self.late)])
        #expect(PermissionExpiry.isStale(request, lastActivity: found))
    }

    @Test("with no session id and two sessions in the folder, nobody speaks for it")
    func twoSessionsSpeakForNobody() {
        let request = Self.model(session: nil)
        let found = Self.activity(
            for: request, sessions: [("s-2", "/w", Self.late), ("s-3", "/w", Self.late)])
        #expect(found == nil)
    }
}

private extension PermissionRequestModel.Summary {
    /// Length of whatever text this summary leads with, for the tests that care that two
    /// samples do not draw to the same height.
    var promptLength: Int {
        if case let .question(prompt, _) = self { return prompt.count }
        return 0
    }
}
