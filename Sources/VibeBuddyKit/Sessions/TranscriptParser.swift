import Foundation

public struct ParsedTail: Sendable, Equatable {
    public var cwd: String?
    public var model: String?
    public var permissionMode: String?
    public var sessionID: String?
    public var agentVersion: String?
    public var effort: String?
    public var gitBranch: String?
    public var action: ToolAction = .none
    /// Human label for the running tool — "édition", "commande"…
    public var status: String = ""
    /// What the tool is pointed at: a file name, a command, a pattern.
    public var subject: String?
    public var lastResultWasError: Bool = false
    public var contextTokens: Int = 0
    public var lastTimestamp: Date?
    public var turnEnded: Bool = false
    /// A question `tool_use` whose id has no matching `tool_result` anywhere newer.
    /// See RFC-003, « Notes d'implémentation ».
    public var awaitingQuestion: Bool = false
    public var question: String?
    public var lastTurnDurationMs: Int?
    var sawResult = false
    var answered: Set<String> = []
    /// Counted so a finishing subagent is never read as the turn finishing: that
    /// mistake alerts on every delegation.
    public var subagentsStarted: Int = 0
    public var subagentsFinished: Int = 0

    public var subagentsRunning: Int { max(0, subagentsStarted - subagentsFinished) }
    /// Entry types the parser did not recognise, with counts. The format is not a
    /// contract (risk R9): counting failures turns silent degradation into a number.
    public var unrecognised: [String: Int] = [:]

    public init() {}
}

/// Closed list by construction: a pending `Bash` and an unanswered question look the
/// same in the transcript. Do not infer a wait from elapsed time.
public enum QuestionTools {

    public static let names: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    public static func asks(_ tool: String) -> Bool { names.contains(tool) }

    public static func summary(tool: String, input: [String: Any]) -> String? {
        if let questions = input["questions"] as? [[String: Any]],
           let first = questions.first {
            if let text = first["question"] as? String, !text.isEmpty { return text }
            if let header = first["header"] as? String, !header.isEmpty { return header }
        }
        if let plan = input["plan"] as? String, !plan.isEmpty { return nil }
        return nil
    }
}

/// Reads a transcript tail: `Data` in, `ParsedTail` out. Entry types and what each
/// carries: see RFC-003, « Notes d'implémentation ».
public enum TranscriptParser {

    public static let maxLines = 80

    public static func parse(_ data: Data) -> ParsedTail {
        var out = ParsedTail()
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)

        // Newest first: for every field, the most recent value is the true one.
        for line in lines.reversed().prefix(maxLines) {
            guard
                let obj = try? JSONSerialization.jsonObject(with: Data(line)),
                let entry = obj as? [String: Any]
            else { continue }

            let type = entry["type"] as? String ?? ""

            take(&out.cwd, entry["cwd"] as? String)
            take(&out.sessionID, (entry["sessionId"] ?? entry["session_id"]) as? String)
            take(&out.agentVersion, entry["version"] as? String)
            take(&out.effort, entry["effort"] as? String)
            take(&out.gitBranch, entry["gitBranch"] as? String)
            if out.lastTimestamp == nil, let ts = entry["timestamp"] as? String {
                out.lastTimestamp = Self.date(from: ts)
            }

            switch type {
            case "assistant", "user":
                absorbMessage(entry, into: &out, isAssistant: type == "assistant")
            case "permission-mode":
                take(&out.permissionMode, entry["permissionMode"] as? String)
            case "system":
                absorbSystem(entry, into: &out)
            case "started":
                out.subagentsStarted += 1
            case "result":
                out.subagentsFinished += 1
            case "attachment", "file-history-snapshot", "file-history-delta",
                 "last-prompt", "mode", "queue-operation", "summary":
                break  // known, nothing needed from them
            case "":
                break
            default:
                out.unrecognised[type, default: 0] += 1
            }
        }
        return out
    }

    // MARK: - Entry kinds

    private static func absorbMessage(
        _ entry: [String: Any], into out: inout ParsedTail, isAssistant: Bool
    ) {
        // Also carried inline here, not only on dedicated `permission-mode` entries.
        take(&out.permissionMode, entry["permissionMode"] as? String)

        guard let message = entry["message"] as? [String: Any] else { return }
        take(&out.model, (message["model"] as? String).flatMap { $0.isEmpty ? nil : $0 })

        // Cache reads and creations count: they are part of what the model was sent.
        if isAssistant, out.contextTokens == 0,
           let usage = message["usage"] as? [String: Any] {
            let input = usage["input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
            out.contextTokens = input + cacheRead + cacheCreate
        }

        guard let content = message["content"] as? [[String: Any]] else { return }

        for block in content {
            switch block["type"] as? String {
            case "tool_result":
                if !out.sawResult {
                    out.sawResult = true
                    out.lastResultWasError = (block["is_error"] as? Bool) ?? false
                }
                if let id = block["tool_use_id"] as? String { out.answered.insert(id) }
            // Past a turn boundary the tool uses belong to a finished turn: letting one
            // set the action makes a done session look busy forever.
            case "tool_use" where out.action == .none && !out.turnEnded:
                let name = block["name"] as? String ?? ""
                let input = block["input"] as? [String: Any] ?? [:]
                // Before the action: `ExitPlanMode` classifies as planning, and would
                // otherwise read as work in progress rather than as a wait.
                if QuestionTools.asks(name),
                   let id = block["id"] as? String, !out.answered.contains(id),
                   !out.awaitingQuestion {
                    out.awaitingQuestion = true
                    out.question = QuestionTools.summary(tool: name, input: input)
                }
                let action = ToolActionClassifier.classify(tool: name, input: input)
                guard action != .none else { continue }
                out.action = action
                out.status = ToolActionClassifier.label(tool: name)
                out.subject = ToolActionClassifier.subject(tool: name, input: input)
            default:
                continue
            }
        }
    }

    private static func absorbSystem(_ entry: [String: Any], into out: inout ParsedTail) {
        switch entry["subtype"] as? String {
        case "turn_duration":
            if out.action == .none && !out.turnEnded {
                out.turnEnded = true
                out.lastTurnDurationMs = entry["durationMs"] as? Int
            }
        default:
            break
        }
    }

    // MARK: - Helpers

    private static func take(_ slot: inout String?, _ value: String?) {
        guard slot == nil, let value, !value.isEmpty else { return }
        slot = value
    }

    /// `ISO8601DateFormatter` is not `Sendable`, so no shared static under Swift 6.
    /// Both the fractional and the plain form occur; accept both or half go nil.
    public static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        return ISO8601DateFormatter().date(from: string)
    }
}
