import Testing
import Foundation
@testable import NotchBuddyKit

@Suite("Transcript parsing")
struct TranscriptParserTests {

    @Test("identity fields are picked up wherever they sit")
    func identityFields() {
        let t = TranscriptParser.parse(TranscriptFixtures.runningShell)
        #expect(t.cwd == TranscriptFixtures.cwd)
        #expect(t.sessionID == TranscriptFixtures.sessionID)
        #expect(t.model == "claude-opus-5")
        #expect(t.agentVersion == "2.1.234")
        #expect(t.gitBranch == "feat/rfc-003")
        #expect(t.lastTimestamp != nil)
    }

    @Test("a running tool becomes an action and a status")
    func toolInProgress() {
        let t = TranscriptParser.parse(TranscriptFixtures.runningShell)
        #expect(t.action == .shell)
        #expect(t.status == "commande")   // libellé lisible, pas le nom brut
        #expect(t.subject == "swift build")
        #expect(!t.turnEnded)
    }

    // Cache reads and creations count: they are part of what the model was sent,
    // and leaving them out understates the context by an order of magnitude.
    @Test("context size sums input, cache reads and cache creation")
    func contextTokens() {
        let t = TranscriptParser.parse(TranscriptFixtures.runningShell)
        #expect(t.contextTokens == 1200 + 48000 + 800)
    }

    @Test("a destructive command reaches the parser as danger")
    func dangerSurfaces() {
        let t = TranscriptParser.parse(TranscriptFixtures.runningDanger)
        #expect(t.action == .danger)
    }
}

// The two findings that decouple this RFC from the hook bridge. The reference
// implementation obtains both from hook events; neither needs one.
@Suite("Signals the reference takes from hooks")
struct TranscriptNativeSignalsTests {

    @Test("turn completion is in the transcript")
    func turnEnd() {
        let t = TranscriptParser.parse(TranscriptFixtures.turnFinished)
        #expect(t.turnEnded)
        #expect(t.lastTurnDurationMs == 3322)
        #expect(t.action == .none)
    }

    @Test("permission mode is in the transcript, as its own entry")
    func permissionModeAsEntry() {
        let t = TranscriptParser.parse(TranscriptFixtures.permissionModeEntry)
        #expect(t.permissionMode == "auto")
    }

    // Found by the R9 counter, not by reading documentation: `started` and
    // `result` carry an `agentId` and track subagents.
    @Test("subagent lifecycle is in the transcript")
    func subagentLifecycle() {
        let t = TranscriptParser.parse(TranscriptFixtures.subagents)
        #expect(t.subagentsStarted == 2)
        #expect(t.subagentsFinished == 1)
        #expect(t.subagentsRunning == 1)
        // A subagent finishing must never read as the turn finishing.
        #expect(!t.turnEnded)
    }

    @Test("permission mode is also carried inline on messages")
    func permissionModeInline() {
        let t = TranscriptParser.parse(TranscriptFixtures.permissionModeInline)
        #expect(t.permissionMode == "plan")
    }
}

@Suite("Parser robustness")
struct TranscriptRobustnessTests {

    @Test("known-but-unused entry types are not counted as unknown")
    func noiseIsSilent() {
        let t = TranscriptParser.parse(TranscriptFixtures.noiseOnly)
        #expect(t.unrecognised.isEmpty)
        #expect(t.action == .none)
    }

    // Risk R9: the transcript format is not a contract. A renamed key would
    // empty the app silently, so what the parser fails to read is counted and
    // exposed rather than dropped.
    @Test("unknown entry types are counted, not swallowed")
    func unknownIsCounted() {
        let t = TranscriptParser.parse(TranscriptFixtures.unknownType)
        #expect(t.unrecognised["some-future-thing"] == 2)
        #expect(t.model == "claude-opus-5")  // still parses what it does know
    }

    // A tail read lands mid-write often enough that this is the normal case,
    // not an edge case.
    @Test("a truncated final line does not lose the rest")
    func truncatedTail() {
        let t = TranscriptParser.parse(TranscriptFixtures.truncatedTail)
        #expect(t.action == .reading)
        #expect(t.model == "claude-opus-5")
    }

    @Test("empty input yields an empty result rather than a crash")
    func emptyInput() {
        let t = TranscriptParser.parse(Data())
        #expect(t.cwd == nil)
        #expect(t.action == .none)
    }

    @Test("both timestamp spellings parse")
    func timestampFormats() {
        #expect(TranscriptParser.date(from: "2026-08-19T16:33:49.396Z") != nil)
        #expect(TranscriptParser.date(from: "2026-08-19T16:33:49Z") != nil)
    }
}

// A pill that says "édition" is less useful than one that says
// "édition de NotchPanel.swift", and every tool hides its subject under a
// different key — there is no common one.
@Suite("Tool subject extraction")
struct ToolSubjectTests {

    @Test("a shell command is its own subject")
    func shellSubject() {
        let t = TranscriptParser.parse(
            TranscriptFixtures.toolUse("Bash", #"{"command":"swift build -c release"}"#))
        #expect(t.status == "commande")
        #expect(t.subject == "swift build -c release")
    }

    // A full path truncated to the pill's width keeps its least informative
    // half, so only the last component is kept.
    @Test("a file path is reduced to its last component")
    func filePathSubject() {
        let t = TranscriptParser.parse(TranscriptFixtures.toolUse(
            "Edit", #"{"file_path":"/Users/dev/Sites/notch/NotchPanel.swift"}"#))
        #expect(t.status == "édition")
        #expect(t.subject == "NotchPanel.swift")
    }

    @Test("every tool hides its subject under its own key", arguments: [
        ("Grep",      #"{"pattern":"WakeCoordinator"}"#,      "recherche",     "WakeCoordinator"),
        ("WebFetch",  #"{"url":"https://example.com/x"}"#,    "web",           "https://example.com/x"),
        ("WebSearch", #"{"query":"swift fsevents"}"#,         "recherche web", "swift fsevents"),
        ("Task",      #"{"description":"auditer les RFC"}"#,  "délégation",    "auditer les RFC"),
    ])
    func subjectKeys(_ tool: String, _ input: String, _ label: String, _ subject: String) {
        let t = TranscriptParser.parse(TranscriptFixtures.toolUse(tool, input))
        #expect(t.status == label)
        #expect(t.subject == subject)
    }

    @Test("a tool with no recognisable subject yields nil rather than noise")
    func noSubject() {
        let t = TranscriptParser.parse(TranscriptFixtures.toolUse("TodoWrite", #"{"todos":[]}"#))
        #expect(t.status == "plan")
        #expect(t.subject == nil)
    }
}

// The `failed` signal, and the third thing RFC-012 expected from a hook.
@Suite("Tool result errors")
struct ToolResultTests {

    @Test("an errored result is detected")
    func errorDetected() {
        #expect(TranscriptParser.parse(TranscriptFixtures.toolError).lastResultWasError)
    }

    @Test("a successful result is not mistaken for an error")
    func successNotError() {
        #expect(!TranscriptParser.parse(TranscriptFixtures.toolSuccess).lastResultWasError)
    }

    @Test("no result at all is not an error")
    func absenceIsNotError() {
        #expect(!TranscriptParser.parse(TranscriptFixtures.runningShell).lastResultWasError)
    }
}

// Scanning newest-first means a completed turn's own tool use is encountered
// *after* the completion marker. Letting it set the current action makes a
// finished session look busy forever, which is exactly the alert that must fire.
@Suite("Turn boundary")
struct TurnBoundaryTests {

    private static let finishedAfterTool = TranscriptFixtures.data([
        TranscriptFixtures.base("assistant", #""message":{"model":"claude-opus-5","content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build"}}]}"#),
        TranscriptFixtures.base("user", #""message":{"content":[{"type":"tool_result","is_error":false,"content":"ok"}]}"#),
        #"{"type":"system","subtype":"turn_duration","durationMs":1200,"sessionId":"s1","cwd":"/Users/dev/notch","timestamp":"2026-08-19T16:00:03.000Z"}"#,
    ])

    @Test("a tool use before the completion marker does not keep the turn open")
    func toolBeforeCompletion() {
        let t = TranscriptParser.parse(Self.finishedAfterTool)
        #expect(t.turnEnded)
        #expect(t.action == .none, "an older turn's tool use leaked into the current action")
    }

    @Test("a tool use after the last completion does keep the turn open")
    func toolAfterCompletion() {
        let t = TranscriptParser.parse(TranscriptFixtures.data([
            #"{"type":"system","subtype":"turn_duration","durationMs":900,"sessionId":"s1","cwd":"/Users/dev/notch","timestamp":"2026-08-19T16:00:00.000Z"}"#,
            TranscriptFixtures.base("assistant", #""message":{"model":"claude-opus-5","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b.swift"}}]}"#),
        ]))
        #expect(t.action == .editing)
        #expect(!t.turnEnded, "a newer tool use means the next turn already started")
    }
}
