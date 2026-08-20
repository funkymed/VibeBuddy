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
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
