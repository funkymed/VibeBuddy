import Foundation

/// What the tail of a transcript says about a session.
public struct ParsedTail: Sendable, Equatable {
    public var cwd: String?
    public var model: String?
    public var permissionMode: String?
    public var sessionID: String?
    public var agentVersion: String?
    /// Reasoning effort, from a top-level `effort` field on assistant entries.
    /// Also mirrored in `~/.claude/settings.json` as `effortLevel`, but the
    /// transcript is per-session and the settings file is global.
    public var effort: String?
    public var gitBranch: String?
    public var action: ToolAction = .none
    /// Human label for the running tool — "édition", "commande"…
    public var status: String = ""
    /// What the tool is pointed at: a file name, a command, a pattern.
    /// The difference between "édition" and "édition de NotchPanel.swift".
    public var subject: String?
    /// The most recent tool result came back as an error.
    ///
    /// Read from `is_error` on a `tool_result` block. This is the `failed`
    /// signal, and like turn completion and permission mode it is in the
    /// transcript rather than behind a hook.
    public var lastResultWasError: Bool = false
    public var contextTokens: Int = 0
    public var lastTimestamp: Date?
    /// True when the most recent meaningful entry is a completed turn — the
    /// agent is done and waiting, not working.
    public var turnEnded: Bool = false
    /// The agent asked the user something and no answer has come back.
    ///
    /// Read from a `tool_use` block whose tool asks a question and whose id has
    /// no matching `tool_result` anywhere newer. **This is in the transcript**,
    /// like the permission mode and the turn boundary before it — the hook was
    /// never needed for it. What the hook is still needed for is a pending
    /// *permission* prompt, which is resolved interactively and written only
    /// once it is over.
    public var awaitingQuestion: Bool = false
    /// The question being waited on, for the row to show.
    public var question: String?
    public var lastTurnDurationMs: Int?
    /// Subagent lifecycle seen in the window, from `started` / `result` entries.
    ///
    /// Tracked so a subagent finishing is never read as the turn finishing —
    /// that mistake would fire an alert on every delegation (RFC-012).
    /// Whether a tool result has already been seen while scanning backwards.
    var sawResult = false
    /// Tool uses already answered, collected while scanning backwards.
    ///
    /// The scan runs newest-first, so a result is always seen *before* the use
    /// it answers. That ordering is what makes this a set membership test rather
    /// than a second pass.
    var answered: Set<String> = []
    public var subagentsStarted: Int = 0
    public var subagentsFinished: Int = 0

    /// Subagents still running in the observed window.
    public var subagentsRunning: Int { max(0, subagentsStarted - subagentsFinished) }
    /// Entry types the parser did not recognise, with counts.
    ///
    /// The transcript format is not a contract (risk R9): a renamed key empties
    /// the app silently. Counting what we failed to read turns a silent
    /// degradation into a number a diagnostics panel can show.
    public var unrecognised: [String: Int] = [:]

    public init() {}
}

/// Tools whose `tool_use` means the agent has stopped and is waiting for a
/// person.
///
/// A closed list on purpose. Any pending `tool_use` looks identical in the
/// transcript — a `Bash` still running and a question nobody answered are both
/// "a use with no result" — so only tools that are *defined* as questions can
/// be read as a wait. Guessing from elapsed time would turn every slow command
/// into a false alert.
public enum QuestionTools {

    /// `AskUserQuestion` is the direct case; `ExitPlanMode` is the same thing in
    /// disguise — the agent stops until the plan is approved or rejected.
    public static let names: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    public static func asks(_ tool: String) -> Bool { names.contains(tool) }

    /// A short label for the row: the first question asked, or the tool's own
    /// meaning when it carries no text.
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

/// Reads the tail of a Claude Code transcript.
///
/// Pure: `Data` in, `ParsedTail` out. No file access, so it can be tested
/// against fixtures rather than against whatever happens to be on the machine.
///
/// # What the format actually contains
///
/// Observed on Claude Code 2.1.234, not taken from the reference implementation,
/// which predates several of these and misses them:
///
/// | type | carries |
/// |---|---|
/// | `user` / `assistant` | messages, `usage`, `tool_use` blocks |
/// | `permission-mode` | `permissionMode` — **the mode is in the transcript** |
/// | `system` / `turn_duration` | the turn ended, with `durationMs` |
/// | `system` / `stop_hook_summary` | a Stop hook ran |
/// | `started` / `result` | subagent lifecycle, keyed by `agentId` |
/// | `attachment`, `file-history-snapshot`, `file-history-delta`, `last-prompt`, `mode`, `queue-operation` | known, unused |
///
/// Three of these matter, and all three are things the reference implementation
/// obtains from hook events that none of them needs: `permission-mode`,
/// `turn_duration`, and the `started`/`result` pair that tracks subagents.
///
/// The last two were not in this list when it was written. They surfaced because
/// unrecognised types are *counted* rather than dropped — the R9 parade paying
/// for itself on its first run.
public enum TranscriptParser {

    /// How far back to look. Entries are scanned newest-first and the first
    /// value found for each field wins, so this only bounds the worst case.
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

            // Fields that can appear on almost any entry.
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
                // A subagent began. Counted so delegation can be shown, and so a
                // finishing subagent is never mistaken for a finishing turn.
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
        // Also carried inline on user/assistant entries, alongside the dedicated
        // `permission-mode` records.
        take(&out.permissionMode, entry["permissionMode"] as? String)

        guard let message = entry["message"] as? [String: Any] else { return }
        take(&out.model, (message["model"] as? String).flatMap { $0.isEmpty ? nil : $0 })

        // Context size: the last assistant turn's prompt tokens. Cache reads and
        // creations count — they are part of what the model was sent.
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
                // Newest-first, so the first result seen is the latest one.
                if !out.sawResult {
                    out.sawResult = true
                    out.lastResultWasError = (block["is_error"] as? Bool) ?? false
                }
                if let id = block["tool_use_id"] as? String { out.answered.insert(id) }
            // Once the scan has passed a turn boundary, everything older
            // belongs to a turn that is already over. Letting one of its tool
            // uses set the current action makes a finished session look busy
            // forever — and silences the alert that says it finished.
            case "tool_use" where out.action == .none && !out.turnEnded:
                let name = block["name"] as? String ?? ""
                let input = block["input"] as? [String: Any] ?? [:]
                // A question with no answer behind it. Checked before the
                // action, because `ExitPlanMode` classifies as planning and
                // would otherwise read as work in progress rather than as a
                // wait — the one distinction this whole feature is about.
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
            // Only meaningful if nothing newer has happened — the loop runs
            // newest-first, so reaching this before any tool use means the turn
            // really is the latest thing in the transcript.
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

    /// Claude Code writes fractional seconds; some entries do not. Both formats
    /// have to be accepted or half the timestamps silently become nil.
    ///
    /// `ISO8601DateFormatter` is not `Sendable`, so it cannot be a shared static
    /// under Swift 6. Built per call instead — this runs at most once per parse,
    /// on a bounded tail, and correctness beats saving an allocation.
    public static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        return ISO8601DateFormatter().date(from: string)
    }
}
