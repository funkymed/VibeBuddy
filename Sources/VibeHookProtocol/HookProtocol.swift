import Foundation

/// Wire format shared by the app and the `vibe-hook` executable.
///
/// This module is deliberately Foundation-only. The hook binary is spawned by
/// Claude Code on every `PreToolUse` — linking AppKit here would make dyld load
/// the whole UI stack before `main()` runs. See RFC-006, decision D4.

/// Claude Code hook events this app registers for.
///
/// The reference implementation registers three and *infers* the rest from
/// transcript inactivity. Claude Code actually exposes fourteen; `stop` and
/// `notification` answer "is it done?" and "does it want me?" directly, which is
/// the whole point of the product. See RFC-012.
public enum HookEventName: String, Codable, Sendable, CaseIterable {
    /// Blocking. The user allows or denies. RFC-007.
    case permissionRequest = "PermissionRequest"
    /// The agent wants the user's attention. RFC-012.
    case notification = "Notification"
    /// The agent finished its turn. RFC-012.
    case stop = "Stop"
    /// The turn ended in failure — distinct from a normal finish. RFC-012.
    case stopFailure = "StopFailure"
    /// A subagent finished. Deliberately registered so RFC-012 can *ignore* it:
    /// treating it as a finish would alert on every delegation.
    case subagentStop = "SubagentStop"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    /// Carry the current `permission_mode`, which is absent from the transcript
    /// between prompts. RFC-003.
    case preToolUse = "PreToolUse"
    case userPromptSubmit = "UserPromptSubmit"

    /// Only `permissionRequest` blocks Claude Code waiting for a reply.
    /// Everything else is fire-and-forget, so its only cost is process startup.
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
///
/// The encoded shape is load-bearing and lives here — and only here. Any extra
/// top-level field makes Claude Code treat the response as invalid and silently
/// fall through to its own prompt, with no error surfaced anywhere. See RFC-006
/// risk R6.
public enum HookDecision: Sendable, Equatable {
    case allow
    case deny(message: String)
}

public enum HookWire {
    /// Unix socket the app listens on.
    public static var socketPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".vibebuddy/buddy.sock")
    }

    /// Upper bound on how long the hook waits for a decision. Bounded so a
    /// wedged app can never block Claude Code indefinitely.
    public static let blockingTimeout: TimeInterval = 120

    /// Exact JSON Claude Code expects. Nothing may be added at the top level.
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
        // Sorted on purpose, and only here. A dictionary has no order, so the
        // bytes would otherwise differ between runs and the golden test of R6
        // would flake instead of catching the thing it exists to catch.
        //
        // Not to be confused with D6, which forbids `.sortedKeys` when writing
        // the *user's* `settings.json` — that one must keep their order.
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}

// MARK: - What the hook reads on stdin

/// One event as Claude Code hands it over: the name, and the raw object.
///
/// The payload is kept as `Data` rather than decoded into fields. The hook's job
/// is to carry it, and every field it learns to read is a field it can break on
/// when Claude Code adds one — the failure mode R6 describes.
public struct HookRequest: Sendable, Equatable {
    public let event: HookEventName
    public let payload: Data

    public init(event: HookEventName, payload: Data) {
        self.event = event
        self.payload = payload
    }

    /// Reads what Claude Code wrote on stdin. `nil` for anything unexpected —
    /// the caller must then exit 0 and let Claude fall back to its own prompt.
    public static func parse(_ stdin: Data) -> HookRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: stdin),
              let dictionary = object as? [String: Any],
              let name = dictionary["hook_event_name"] as? String,
              let event = HookEventName(rawValue: name)
        else { return nil }
        return HookRequest(event: event, payload: stdin)
    }
}

// MARK: - The line protocol between the hook and the app

/// One JSON object per line, in both directions. A line, not a length prefix:
/// the payload is already JSON and JSON never contains a bare newline, so the
/// framing costs one byte and stays readable in a `nc` session when something
/// goes wrong at three in the morning.
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
