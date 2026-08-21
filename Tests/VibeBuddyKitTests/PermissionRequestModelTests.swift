import Foundation
import Testing
import VibeHookProtocol
@testable import VibeBuddyKit

@Suite("Reading a permission request")
struct PermissionRequestModelTests {

    /// Builds the payload a `PermissionRequest` hook actually receives.
    static func request(tool: String, input: [String: Any],
                        extra: [String: Any] = [:]) -> HookRequest {
        var root: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "s-1",
            "cwd": "/Users/x/Sites/notch",
            "transcript_path": "/Users/x/.claude/projects/notch/s-1.jsonl",
            "tool_use_id": "toolu_1",
            "tool_name": tool,
            "tool_input": input,
        ]
        root.merge(extra) { _, new in new }
        return HookRequest(
            event: .permissionRequest,
            payload: try! JSONSerialization.data(withJSONObject: root))
    }

    static func parsed(tool: String, input: [String: Any],
                       extra: [String: Any] = [:]) -> PermissionRequestModel {
        PermissionRequestModel.parse(request(tool: tool, input: input, extra: extra))!
    }

    // MARK: - The envelope

    @Test("the envelope is kept, so a request can be matched to its session")
    func envelope() {
        let model = Self.parsed(tool: "Bash", input: ["command": "ls"])
        #expect(model.id == "toolu_1")
        #expect(model.toolName == "Bash")
        #expect(model.sessionID == "s-1")
        #expect(model.cwd == "/Users/x/Sites/notch")
        #expect(model.transcriptPath?.hasSuffix("s-1.jsonl") == true)
    }

    // A request with no id still has to be tellable from the next one, or a
    // queue cannot hold two of them.
    @Test("a request with no id is given one")
    func missingIdentifier() {
        var root: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": ["command": "ls"],
        ]
        func parse() -> PermissionRequestModel? {
            PermissionRequestModel.parse(HookRequest(
                event: .permissionRequest,
                payload: try! JSONSerialization.data(withJSONObject: root)))
        }
        let first = parse()
        let second = parse()
        #expect(first?.id.isEmpty == false)
        #expect(first?.id != second?.id)
        root["tool_name"] = "Bash"
    }

    @Test("something that is not a JSON object is refused rather than guessed at")
    func rubbishIsRefused() {
        let request = HookRequest(event: .permissionRequest, payload: Data("[1,2,3]".utf8))
        #expect(PermissionRequestModel.parse(request) == nil)
    }

    // MARK: - Per tool

    @Test("a Bash request is a command line")
    func shell() {
        let model = Self.parsed(tool: "Bash", input: [
            "command": "rm -rf build", "description": "Nettoyer le dossier de build",
        ])
        guard case let .shell(command, description) = model.summary else {
            Issue.record("attendu .shell, obtenu \(model.summary)"); return
        }
        #expect(command == "rm -rf build")
        #expect(description == "Nettoyer le dossier de build")
    }

    @Test("an Edit is a diff, and a MultiEdit is its first one")
    func diffs() {
        let single = Self.parsed(tool: "Edit", input: [
            "file_path": "/a/b.swift", "old_string": "avant", "new_string": "après",
        ])
        guard case let .diff(path, before, after) = single.summary else {
            Issue.record("attendu .diff, obtenu \(single.summary)"); return
        }
        #expect(path == "/a/b.swift")
        #expect(before == "avant")
        #expect(after == "après")

        let multi = Self.parsed(tool: "MultiEdit", input: [
            "file_path": "/a/b.swift",
            "edits": [
                ["old_string": "un", "new_string": "deux"],
                ["old_string": "trois", "new_string": "quatre"],
            ],
        ])
        guard case let .diff(_, first, second) = multi.summary else {
            Issue.record("attendu .diff, obtenu \(multi.summary)"); return
        }
        #expect(first == "un")
        #expect(second == "deux")
    }

    @Test("Write and Read ask for different things")
    func filesInAndOut() {
        let write = Self.parsed(tool: "Write", input: [
            "file_path": "/a/new.txt", "content": "bonjour",
        ])
        guard case let .write(path, contents) = write.summary else {
            Issue.record("attendu .write, obtenu \(write.summary)"); return
        }
        #expect(path == "/a/new.txt")
        #expect(contents == "bonjour")

        let read = Self.parsed(tool: "Read", input: ["file_path": "/etc/hosts"])
        #expect(read.summary == .read(path: "/etc/hosts"))
    }

    @Test("a fetch is a URL")
    func fetch() {
        let model = Self.parsed(tool: "WebFetch", input: ["url": "https://example.invalid"])
        #expect(model.summary == .url("https://example.invalid"))
    }

    // MARK: - The question, whose shape has moved before

    @Test("a question is found under `questions[0]`, or on its own")
    func questionShapes() {
        let nested = Self.parsed(tool: "AskUserQuestion", input: [
            "questions": [[
                "question": "On garde laquelle ?",
                "options": [["label": "Coral"], ["label": "Bitcount"]],
            ]],
        ])
        #expect(nested.summary == .question(
            prompt: "On garde laquelle ?", options: ["Coral", "Bitcount"]))

        let flat = Self.parsed(tool: "AskUserQuestion", input: [
            "question": "Continuer ?", "options": ["Oui", "Non"],
        ])
        #expect(flat.summary == .question(prompt: "Continuer ?", options: ["Oui", "Non"]))
    }

    // The three key names have all been seen. A missed option is an answer the
    // user cannot give.
    @Test("options are read under label, value or text", arguments: ["label", "value", "text"])
    func optionKeys(_ key: String) {
        let model = Self.parsed(tool: "AskUserQuestion", input: [
            "question": "?", "options": [[key: "Choix A"], [key: "Choix B"]],
        ])
        #expect(model.summary == .question(prompt: "?", options: ["Choix A", "Choix B"]))
    }

    @Test("a plan is a question with no options")
    func exitPlanMode() {
        let model = Self.parsed(tool: "ExitPlanMode", input: ["plan": "1. faire ceci"])
        #expect(model.summary == .question(prompt: "1. faire ceci", options: []))
    }

    // MARK: - What the app has never heard of

    @Test("an unknown tool still produces a request, in a stable order")
    func unknownTool() {
        let model = Self.parsed(tool: "SomeFutureTool", input: [
            "zeta": "dernier", "alpha": "premier", "count": 3,
        ])
        guard case let .other(fields) = model.summary else {
            Issue.record("attendu .other, obtenu \(model.summary)"); return
        }
        // Sorted: a dictionary has no order, and a panel that reshuffles its own
        // fields between two frames is a panel nobody can read.
        #expect(fields.map(\.name) == ["alpha", "count", "zeta"])
        #expect(fields.first?.value == "premier")
        #expect(fields.first(where: { $0.name == "count" })?.value == "3")
    }

    @Test("an unknown tool with a hundred fields does not carry a hundred fields")
    func unknownToolIsBounded() {
        var input: [String: Any] = [:]
        for index in 0..<100 { input["k\(index)"] = "v" }
        let model = Self.parsed(tool: "Whatever", input: input)
        guard case let .other(fields) = model.summary else { return }
        #expect(fields.count == PermissionRequestModel.unknownFieldLimit)
    }

    // MARK: - Truncation, at the storage and not at the view

    @Test("a huge string is cut when it is parsed, not when it is drawn")
    func truncatesAtParseTime() {
        let huge = String(repeating: "x", count: 200_000)
        let model = Self.parsed(tool: "Write", input: ["file_path": "/a", "content": huge])
        guard case let .write(_, contents) = model.summary else {
            Issue.record("attendu .write"); return
        }
        #expect(contents.count < PermissionRequestModel.diffLimit + 100)
        // And it says what it dropped: the count is the difference between a
        // panel that summarises and one that hides.
        #expect(contents.contains("caractères de plus"))
    }

    @Test("a string that fits is left exactly as it was")
    func shortStringsAreUntouched() {
        let model = Self.parsed(tool: "Bash", input: ["command": "ls -la"])
        #expect(model.summary == .shell(command: "ls -la", description: nil))
    }

    // MARK: - Suggestions

    // Claude Code owns its pattern language (`Bash(npm install:*)`).
    // Reimplementing it is how the two drift apart, so it is carried verbatim.
    @Test("suggestions are carried through as they came, in both shapes")
    func suggestionsAreVerbatim() {
        let strings = Self.parsed(
            tool: "Bash", input: ["command": "npm install"],
            extra: ["permission_suggestions": ["Bash(npm install:*)", "Bash"]])
        #expect(strings.suggestions == ["Bash(npm install:*)", "Bash"])

        let objects = Self.parsed(
            tool: "Bash", input: ["command": "npm install"],
            extra: ["permission_suggestions": [["rule": "Bash(npm install:*)"]]])
        #expect(objects.suggestions == ["Bash(npm install:*)"])
    }

    @Test("no suggestions is not an error")
    func noSuggestions() {
        #expect(Self.parsed(tool: "Bash", input: ["command": "ls"]).suggestions.isEmpty)
    }
}
