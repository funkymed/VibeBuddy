import Foundation

/// One line of a session's recent history.
public struct TimelineEvent: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case prompt
        case tool(ToolLabel)
        /// A `tool_result`, carrying whether it failed.
        case result(failed: Bool)
        /// End of a turn, with its duration when the entry gives one.
        case turnEnd(milliseconds: Int?)
        case subagentStarted
        case subagentFinished
    }

    public let id: String
    public let at: Date?
    public let kind: Kind
    /// Truncated at parse time, never at render time: holding whole prompts in memory
    /// is how the transcript budget gets multiplied (R2).
    public let text: String

    public init(id: String, at: Date?, kind: Kind, text: String) {
        self.id = id; self.at = at; self.kind = kind; self.text = text
    }
}

/// Reads a transcript tail into the events a person would recognise.
public enum TimelineParser {
    public static let maxEvents = 40
    public static let maxTextLength = 140

    public static func parse(_ data: Data) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)

        for (index, line) in lines.enumerated() {
            guard
                let obj = try? JSONSerialization.jsonObject(with: Data(line)),
                let entry = obj as? [String: Any]
            else { continue }

            let at = (entry["timestamp"] as? String).flatMap(TranscriptParser.date(from:))
            let stamp = (entry["uuid"] as? String) ?? "\(index)"

            switch entry["type"] as? String {
            case "user":
                absorbUser(entry, id: stamp, at: at, into: &events)
            case "assistant":
                absorbAssistant(entry, id: stamp, at: at, into: &events)
            case "system":
                guard entry["subtype"] as? String == "turn_duration" else { continue }
                events.append(TimelineEvent(
                    id: stamp, at: at,
                    kind: .turnEnd(milliseconds: entry["durationMs"] as? Int), text: ""))
            case "started":
                events.append(TimelineEvent(
                    id: stamp, at: at, kind: .subagentStarted,
                    text: clip(entry["description"] as? String ?? "")))
            case "result":
                events.append(TimelineEvent(
                    id: stamp, at: at, kind: .subagentFinished, text: ""))
            default:
                continue
            }
        }

        return Array(events.suffix(maxEvents))
    }

    /// A `tool_result` arrives as a `user` entry, which is why this cannot key on the
    /// entry type alone.
    private static func absorbUser(
        _ entry: [String: Any], id: String, at: Date?, into events: inout [TimelineEvent]
    ) {
        guard let message = entry["message"] as? [String: Any] else { return }

        if let text = message["content"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            events.append(TimelineEvent(id: id, at: at, kind: .prompt, text: clip(trimmed)))
            return
        }

        guard let blocks = message["content"] as? [[String: Any]] else { return }
        for (offset, block) in blocks.enumerated() {
            switch block["type"] as? String {
            case "tool_result":
                events.append(TimelineEvent(
                    id: "\(id)-r\(offset)", at: at,
                    kind: .result(failed: (block["is_error"] as? Bool) ?? false),
                    text: ""))
            case "text":
                let text = (block["text"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                events.append(TimelineEvent(
                    id: "\(id)-t\(offset)", at: at, kind: .prompt, text: clip(text)))
            default:
                continue
            }
        }
    }

    private static func absorbAssistant(
        _ entry: [String: Any], id: String, at: Date?, into events: inout [TimelineEvent]
    ) {
        guard let message = entry["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]]
        else { return }

        for (offset, block) in blocks.enumerated() {
            guard block["type"] as? String == "tool_use" else { continue }
            let name = block["name"] as? String ?? ""
            let input = block["input"] as? [String: Any] ?? [:]
            events.append(TimelineEvent(
                id: "\(id)-u\(offset)", at: at,
                kind: .tool(ToolActionClassifier.label(tool: name)),
                text: clip(ToolActionClassifier.subject(tool: name, input: input) ?? "")))
        }
    }

    /// Collapses the newlines too: a timeline row is one line tall, and a prompt that
    /// keeps its own would push every following row off the panel.
    static func clip(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > maxTextLength else { return flat }
        return String(flat.prefix(maxTextLength)) + "…"
    }
}
