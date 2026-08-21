import Foundation
import VibeHookProtocol

/// One permission request, parsed into something a view can draw.
///
/// **Truncated at parse time, not at display time.** A `tool_input` carries
/// whatever Claude is about to do: an `Edit`'s `new_string` can be a whole file,
/// and a `Write` can be larger still. Keeping it whole to shorten it in a view
/// means the app's memory follows the size of the user's files, for a panel that
/// shows twenty lines. RFC-007, T1.
///
/// Every field is optional except the tool's name, and an unknown tool still
/// produces a request. The schema is not a contract (R9), and the failure mode
/// to avoid is silence: a request that fails to parse must still reach the user,
/// even as a list of raw fields.
public struct PermissionRequestModel: Sendable, Equatable, Identifiable {

    /// Longest string kept from any single field.
    public static let fieldLimit = 4_000
    /// Longest text kept for the two sides of a diff.
    public static let diffLimit = 8_000
    /// Most fields kept for a tool this app knows nothing about.
    public static let unknownFieldLimit = 12

    /// Opening of the line appended in place of what was dropped. Public because
    /// the diff view has to tell that line apart from the file's own text: it is
    /// not part of the change, so it must not be painted as one.
    public static let truncationMark = "… ("

    public let id: String
    public let toolName: String
    public let sessionID: String?
    public let cwd: String?
    /// Given on every event since the hook contract was read — RFC-006, Q1.
    public let transcriptPath: String?
    public let summary: Summary
    /// What Claude Code offers to remember, verbatim. Never parsed: its pattern
    /// language is its own (`Bash(npm install:*)`), and reimplementing it is how
    /// the two drift apart.
    public let suggestions: [String]
    public let receivedAt: Date
    /// PID of the `claude` process, when the socket could name it.
    public let pid: pid_t?

    public init(
        id: String, toolName: String, sessionID: String? = nil, cwd: String? = nil,
        transcriptPath: String? = nil, summary: Summary, suggestions: [String] = [],
        receivedAt: Date = Date(), pid: pid_t? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.summary = summary
        self.suggestions = suggestions
        self.receivedAt = receivedAt
        self.pid = pid
    }

    /// What the request is asking for, by kind rather than by tool name.
    ///
    /// Two tools that ask the same thing get the same case: `Edit` and
    /// `MultiEdit` are both a diff, `Write` and `NotebookEdit` are both a file
    /// being replaced. The view draws the kind; the tool's name is shown as a
    /// label beside it.
    public enum Summary: Sendable, Equatable {
        /// A command line, and the description Claude wrote for it.
        case shell(command: String, description: String?)
        /// A file changing, with the two sides already cut to size.
        case diff(path: String, before: String, after: String)
        /// A file being created or replaced whole.
        case write(path: String, contents: String)
        /// Reading a file, which asks for a path and nothing else.
        case read(path: String)
        case url(String)
        /// `AskUserQuestion` and `ExitPlanMode`: the agent is waiting on a
        /// person, and the hook has no channel to answer with. See RFC-007 §3.
        case question(prompt: String, options: [String])
        /// Anything this app has never heard of, kept as it came.
        case other(fields: [Field])

        public struct Field: Sendable, Equatable {
            public let name: String
            public let value: String
            public init(name: String, value: String) {
                self.name = name
                self.value = value
            }
        }
    }
}

// MARK: - Parsing

public extension PermissionRequestModel {

    /// Builds a request from what the hook forwarded.
    ///
    /// `nil` only when the payload is not a JSON object at all — anything else,
    /// however unexpected, comes back as a request. A permission the app fails
    /// to render is a permission the user never sees, and Claude waits.
    static func parse(_ request: HookRequest, from pid: pid_t? = nil,
                      at now: Date = Date()) -> PermissionRequestModel? {
        guard let root = (try? JSONSerialization.jsonObject(with: request.payload))
                as? [String: Any]
        else { return nil }

        let input = root["tool_input"] as? [String: Any] ?? [:]
        let tool = root["tool_name"] as? String ?? "?"

        return PermissionRequestModel(
            id: (root["tool_use_id"] as? String)
                ?? (input["id"] as? String)
                ?? UUID().uuidString,
            toolName: tool,
            sessionID: root["session_id"] as? String,
            cwd: root["cwd"] as? String,
            transcriptPath: root["transcript_path"] as? String,
            summary: summarise(tool: tool, input: input),
            suggestions: suggestions(from: root),
            receivedAt: now,
            pid: pid)
    }

    /// `permission_suggestions` as strings, whatever shape it arrives in.
    ///
    /// Seen as a list of strings and as a list of objects carrying a rule; both
    /// are accepted, and anything else is dropped rather than guessed at.
    static func suggestions(from root: [String: Any]) -> [String] {
        guard let raw = root["permission_suggestions"] as? [Any] else { return [] }
        return raw.compactMap { entry in
            if let text = entry as? String { return text }
            guard let object = entry as? [String: Any] else { return nil }
            return (object["rule"] ?? object["pattern"] ?? object["value"]) as? String
        }
    }

    static func summarise(tool: String, input: [String: Any]) -> Summary {
        func text(_ key: String, limit: Int = fieldLimit) -> String? {
            guard let value = input[key] as? String else { return nil }
            return value.cut(to: limit)
        }

        switch tool {
        case "Bash", "BashOutput", "KillShell":
            return .shell(
                command: text("command") ?? text("description") ?? "",
                description: input["description"] as? String)

        case "Edit", "MultiEdit", "StrReplace":
            // A `MultiEdit` carries its pairs in `edits`; the first one is what
            // the panel shows, and the count is in the tool's own label.
            if let edits = input["edits"] as? [[String: Any]], let first = edits.first {
                return .diff(
                    path: (input["file_path"] as? String) ?? "",
                    before: ((first["old_string"] as? String) ?? "").cut(to: diffLimit),
                    after: ((first["new_string"] as? String) ?? "").cut(to: diffLimit))
            }
            return .diff(
                path: text("file_path") ?? "",
                before: text("old_string", limit: diffLimit) ?? "",
                after: text("new_string", limit: diffLimit) ?? "")

        case "Write", "NotebookEdit":
            return .write(
                path: text("file_path") ?? text("notebook_path") ?? "",
                contents: text("content", limit: diffLimit)
                    ?? text("new_source", limit: diffLimit) ?? "")

        case "Read", "NotebookRead":
            return .read(path: text("file_path") ?? text("notebook_path") ?? "")

        case "WebFetch", "WebSearch":
            return .url(text("url") ?? text("query") ?? "")

        case "AskUserQuestion", "ExitPlanMode":
            let parsed = question(from: input)
            return .question(prompt: parsed.prompt, options: parsed.options)

        default:
            return .other(fields: fields(from: input))
        }
    }

    /// The prompt and its options, out of a shape that has changed before.
    ///
    /// Accepts `questions[0]`, a bare `question`, and a `plan`; options as
    /// objects keyed `label`, `value` or `text`, or as plain strings. Tolerant
    /// on purpose: this is the one tool whose payload the app has already seen
    /// arrive in more than one shape, and a missed option is an answer the user
    /// cannot give.
    static func question(from input: [String: Any]) -> (prompt: String, options: [String]) {
        var scope = input
        if let questions = input["questions"] as? [[String: Any]], let first = questions.first {
            scope = first
        }
        let prompt = (scope["question"] as? String)
            ?? (scope["prompt"] as? String)
            ?? (scope["header"] as? String)
            ?? (input["plan"] as? String)
            ?? ""

        let raw = (scope["options"] as? [Any]) ?? (scope["choices"] as? [Any]) ?? []
        let options = raw.compactMap { entry -> String? in
            if let text = entry as? String { return text }
            guard let object = entry as? [String: Any] else { return nil }
            return ((object["label"] ?? object["value"] ?? object["text"]) as? String)
        }
        return (prompt.cut(to: fieldLimit), options.map { $0.cut(to: 200) })
    }

    /// An unknown tool's input, flattened. Sorted, because a dictionary has no
    /// order and a panel that reshuffles its own fields between two frames is
    /// a panel nobody can read.
    static func fields(from input: [String: Any]) -> [Summary.Field] {
        input.keys.sorted().prefix(unknownFieldLimit).map { key in
            let value = input[key]
            let text: String
            switch value {
            case let string as String: text = string
            case let number as NSNumber: text = number.stringValue
            case .none: text = ""
            case let other?: text = String(describing: other)
            }
            return Summary.Field(name: key, value: text.cut(to: fieldLimit))
        }
    }
}

extension String {
    /// At most `limit` characters, with what was dropped said out loud.
    ///
    /// The count matters: « 4 000 premiers caractères sur 180 000 » is the
    /// difference between a panel that summarises and a panel that hides.
    func cut(to limit: Int) -> String {
        guard count > limit else { return self }
        let kept = prefix(limit)
        return "\(kept)\n\(PermissionRequestModel.truncationMark)\(count - limit) caractères de plus)"
    }
}
