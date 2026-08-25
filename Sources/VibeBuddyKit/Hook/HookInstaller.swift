import Foundation
import VibeHookProtocol

/// Registers — and unregisters — `vibe-hook` in `~/.claude/settings.json`.
public struct HookInstaller: Sendable {
    /// The key stamped into every entry we own, and the only thing that makes an entry
    /// ours.
    public static let markerKey = "vibebuddy"
    /// Bumped only if the shape of an entry changes in a way that needs migrating.
    public static let markerValue = "1"

    /// Name of the hook executable, and the fallback way of recognising an entry whose
    /// marker was lost to a hand edit.
    public static let executableName = "vibe-hook"

    public let hookPath: String
    public let writer: ClaudeSettingsWriter

    /// - Parameter hookPath: defaults to `vibe-hook` sitting next to the running
    /// executable — `Contents/MacOS/` in a bundle, `.build/release/` in a dev build.
    public init(hookPath: String? = nil, writer: ClaudeSettingsWriter = ClaudeSettingsWriter()) {
        self.hookPath = hookPath ?? Self.defaultHookPath()
        self.writer = writer
    }

    public static func defaultHookPath() -> String {
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        return executable.deletingLastPathComponent()
            .appendingPathComponent(executableName).path
    }

    /// - Returns: true if the file changed, false if it was already correct.
    @discardableResult
    public func install() throws -> Bool {
        try writer.mutate { Self.installing($0, hookPath: hookPath) }
    }

    /// - Returns: true if the file changed, false if nothing of ours was in it.
    @discardableResult
    public func uninstall() throws -> Bool {
        try writer.mutate { Self.removing($0) }
    }

    /// What the file would become, without writing it.
    public func preview(_ settings: OrderedJSON) -> OrderedJSON {
        Self.installing(settings, hookPath: hookPath)
    }

    /// Registers every event of `HookEventName`, cleans up entries of ours that point
    /// somewhere else or name an event we no longer register, and leaves everything else
    /// exactly where it was.
    public static func installing(_ settings: OrderedJSON, hookPath: String) -> OrderedJSON {
        let wanted = Set(HookEventName.allCases.map(\.rawValue))
        var hooks = settings["hooks"] ?? .object([])
        guard hooks.objectPairs != nil else {
            // Someone put something that is not an object under "hooks".
            return settings
        }

        // Events we used to register and no longer do: strip ours, keep theirs.
        for pair in hooks.objectPairs ?? [] where !wanted.contains(pair.key) {
            hooks = hooks.setting(pair.key, to: pruned(stripped(pair.value)))
        }

        for event in HookEventName.allCases {
            let existing = hooks[event.rawValue] ?? .array([])
            hooks = hooks.setting(
                event.rawValue,
                to: placed(entry(hookPath: hookPath), in: existing))
        }

        return settings.setting("hooks", to: hooks)
    }

    /// Removes our entries from every event, ours or not, and prunes whatever they leave
    /// empty behind them.
    public static func removing(_ settings: OrderedJSON) -> OrderedJSON {
        guard let hooks = settings["hooks"], hooks.objectPairs != nil else { return settings }

        var cleaned = hooks
        for pair in hooks.objectPairs ?? [] {
            cleaned = cleaned.setting(pair.key, to: pruned(stripped(pair.value)))
        }
        // An empty "hooks" object is not information, and leaving it behind on a
        // machine where we created it would show up in that same diff.
        let remaining = cleaned.objectPairs ?? []
        return settings.setting("hooks", to: remaining.isEmpty ? nil : cleaned)
    }

    /// `{"type":"command","command":"…/vibe-hook","vibebuddy":"1"}`
    static func entry(hookPath: String) -> OrderedJSON {
        .object([
            ("type", .string("command")),
            ("command", .string(hookPath)),
            (markerKey, .string(markerValue)),
        ])
    }

    /// A matcher on every event, including those where Claude Code ignores it.
    static func group(hookPath: String) -> OrderedJSON {
        .object([
            ("matcher", .string("*")),
            ("hooks", .array([entry(hookPath: hookPath)])),
        ])
    }

    public static func isOurs(_ entry: OrderedJSON) -> Bool {
        if case .string = entry[markerKey] { return true }
        // Marker lost to a hand edit, or written by a version that predates it: still
        // ours, and still ours to clean up.
        if case let .string(command)? = entry["command"] {
            return (command as NSString).lastPathComponent == executableName
        }
        return false
    }

    /// Puts our entry in `array` exactly once, in place when one is already there.
    private static func placed(_ entry: OrderedJSON, in array: OrderedJSON) -> OrderedJSON {
        guard case let .array(groups) = array else {
            // Not an array — not ours to reinterpret.
            return array
        }

        var out: [OrderedJSON] = []
        var placed = false

        for group in groups {
            guard case let .array(inner)? = group["hooks"] else {
                out.append(group)
                continue
            }
            var kept: [OrderedJSON] = []
            for candidate in inner {
                guard isOurs(candidate) else { kept.append(candidate); continue }
                if !placed {
                    kept.append(entry)   // replaced where it stood
                    placed = true
                }
                // Any further entry of ours in the same file is a duplicate.
            }
            if kept.isEmpty { continue }  // the group held only ours
            out.append(group.setting("hooks", to: .array(kept)))
        }

        if !placed { out.append(group(hookPath: entryPath(entry))) }
        return .array(out)
    }

    private static func entryPath(_ entry: OrderedJSON) -> String {
        if case let .string(command)? = entry["command"] { return command }
        return defaultHookPath()
    }

    /// Removes our entries from every group of one event's array.
    private static func stripped(_ array: OrderedJSON) -> OrderedJSON {
        guard case let .array(groups) = array else { return array }
        var out: [OrderedJSON] = []
        for group in groups {
            guard case let .array(inner)? = group["hooks"] else {
                out.append(group)
                continue
            }
            let kept = inner.filter { !isOurs($0) }
            if kept.isEmpty { continue }
            out.append(group.setting("hooks", to: .array(kept)))
        }
        return .array(out)
    }

    /// An event whose array we emptied loses its key entirely.
    private static func pruned(_ array: OrderedJSON) -> OrderedJSON? {
        if case let .array(groups) = array, groups.isEmpty { return nil }
        return array
    }
}
