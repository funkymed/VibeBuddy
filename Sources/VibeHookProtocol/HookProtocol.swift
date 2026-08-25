import Foundation

/// Wire format shared by the app and the `vibe-hook` executable.

/// Claude Code hook events this app registers for.
public enum HookEventName: String, Codable, Sendable, CaseIterable {
    /// Blocking.
    case permissionRequest = "PermissionRequest"
    /// The agent wants the user's attention.
    case notification = "Notification"
    /// The agent finished its turn.
    case stop = "Stop"
    /// The turn ended in failure — distinct from a normal finish.
    case stopFailure = "StopFailure"
    case subagentStop = "SubagentStop"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    /// Carry the current `permission_mode`, which is absent from the transcript between
    /// prompts.
    case preToolUse = "PreToolUse"
    case userPromptSubmit = "UserPromptSubmit"

    /// Only `permissionRequest` blocks Claude Code waiting for a reply.
    public var isBlocking: Bool { self == .permissionRequest }
}

public struct ModeUpdate: Codable, Sendable, Equatable {
    public let cwd: String
    public let permissionMode: String
    public let sessionID: String

    public init(cwd: String, permissionMode: String, sessionID: String) {
        self.cwd = cwd
        self.permissionMode = permissionMode
        self.sessionID = sessionID
    }
}

/// The decision handed back to Claude Code.
public enum HookDecision: Sendable, Equatable {
    case allow
    case deny(message: String)
}

public enum HookWire {
    /// Unix socket the app listens on.
    public static var socketPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".vibebuddy/buddy.sock")
    }

    /// Upper bound on how long the hook waits for a decision.
    public static let blockingTimeout: TimeInterval = 120

    /// Exact JSON Claude Code expects.
    public static func encode(_ decision: HookDecision) throws -> Data {
        let inner: [String: Any]
        switch decision {
        case .allow:
            inner = ["behavior": "allow"]
        case let .deny(message):
            inner = ["behavior": "deny", "message": message]
        }
        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": HookEventName.permissionRequest.rawValue,
                "decision": inner,
            ]
        ]
        // Sorted on purpose, and only here.
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

/// One event as Claude Code hands it over: the name, and the raw object.
public struct HookRequest: Sendable, Equatable {
    public let event: HookEventName
    public let payload: Data

    public init(event: HookEventName, payload: Data) {
        self.event = event
        self.payload = payload
    }

    /// Reads what Claude Code wrote on stdin.
    public static func parse(_ stdin: Data) -> HookRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: stdin),
              let dictionary = object as? [String: Any],
              let name = dictionary["hook_event_name"] as? String,
              let event = HookEventName(rawValue: name)
        else { return nil }
        return HookRequest(event: event, payload: stdin)
    }
}

/// One JSON object per line, in both directions.
public enum HookLine {
    public static let version = 1

    public static func encodeRequest(_ request: HookRequest) throws -> Data {
        let payload = (try? JSONSerialization.jsonObject(with: request.payload)) ?? [:]
        var line = try JSONSerialization.data(withJSONObject: [
            "v": version,
            "event": request.event.rawValue,
            "payload": payload,
        ])
        line.append(0x0A)
        return line
    }

    public static func decodeRequest(_ line: Data) -> HookRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let dictionary = object as? [String: Any],
              dictionary["v"] as? Int == version,
              let name = dictionary["event"] as? String,
              let event = HookEventName(rawValue: name),
              let payload = dictionary["payload"],
              let data = try? JSONSerialization.data(withJSONObject: payload)
        else { return nil }
        return HookRequest(event: event, payload: data)
    }

    public static func encodeDecision(_ decision: HookDecision) throws -> Data {
        var body: [String: Any] = [:]
        switch decision {
        case .allow:
            body["behavior"] = "allow"
        case let .deny(message):
            body["behavior"] = "deny"
            body["message"] = message
        }
        var line = try JSONSerialization.data(withJSONObject: body)
        line.append(0x0A)
        return line
    }

    public static func decodeDecision(_ line: Data) -> HookDecision? {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let dictionary = object as? [String: Any],
              let behavior = dictionary["behavior"] as? String
        else { return nil }
        switch behavior {
        case "allow": return .allow
        case "deny":  return .deny(message: dictionary["message"] as? String ?? "")
        default:      return nil
        }
    }
}
