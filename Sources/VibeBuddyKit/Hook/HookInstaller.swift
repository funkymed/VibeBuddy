import Foundation
import VibeHookProtocol

/// Registers — and unregisters — `vibe-hook` in `~/.claude/settings.json`.
///
/// Everything here goes through `ClaudeSettingsWriter` (decision D6), which is
/// what makes the write atomic, backed up and order-preserving. This type only
/// decides *what* the file should contain; it never touches it directly.
///
/// Two properties matter more than the feature itself:
///
/// - **Idempotent.** An installation that is already correct writes nothing at
///   all — not even a re-serialisation of identical bytes. `mutate` returns
///   false, no backup is taken, and the modification date is left alone.
/// - **Non-destructive.** Hooks the user wrote themselves, events this app
///   knows nothing about, and every other key in the file survive untouched.
///   Only entries carrying our marker are ever removed.
///
/// The reference implementation recognised its own entries by
/// `cmd.hasSuffix(" --hook")`, which worked because its hook was the app binary
/// with a flag. With a separate executable that heuristic means nothing, so the
/// entry carries an explicit marker instead. See RFC-006, T8 and T9.
public struct HookInstaller: Sendable {

    /// The key stamped into every entry we own, and the only thing that makes
    /// an entry ours. A path is not enough: the user may move the app, and a
    /// stale path must still be recognised as ours so it can be cleaned up.
    public static let markerKey = "vibebuddy"
    /// Bumped only if the shape of an entry changes in a way that needs
    /// migrating. Recognition does not depend on the value.
    public static let markerValue = "1"

    /// Name of the hook executable, and the fallback way of recognising an
    /// entry whose marker was lost to a hand edit.
    public static let executableName = "vibe-hook"

    public let hookPath: String
    public let writer: ClaudeSettingsWriter

    /// - Parameter hookPath: defaults to `vibe-hook` sitting next to the
    ///   running executable — `Contents/MacOS/` in a bundle, `.build/release/`
    ///   in a dev build. `scripts/build.sh:53` puts it there.
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

    // MARK: - Doing it

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

    /// What the file would become, without writing it. Used by the CLI to show
    /// the diff before asking for consent, and by the tests.
    public func preview(_ settings: OrderedJSON) -> OrderedJSON {
        Self.installing(settings, hookPath: hookPath)
    }

    // MARK: - The pure part

    /// Registers every event of `HookEventName`, cleans up entries of ours that
    /// point somewhere else or name an event we no longer register, and leaves
    /// everything else exactly where it was.
    public static func installing(_ settings: OrderedJSON, hookPath: String) -> OrderedJSON {
        let wanted = Set(HookEventName.allCases.map(\.rawValue))
        var hooks = settings["hooks"] ?? .object([])
        guard hooks.objectPairs != nil else {
            // Someone put something that is not an object under "hooks". Not
            // ours to reinterpret — leave the file alone.
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

    /// Removes our entries from every event, ours or not, and prunes whatever
    /// they leave empty behind them. The exit criterion of T9 is a `diff`
    /// against the backup showing *exactly* our entries gone, so an emptied
    /// group or an emptied event array must not be left behind as residue.
    public static func removing(_ settings: OrderedJSON) -> OrderedJSON {
        guard let hooks = settings["hooks"], hooks.objectPairs != nil else { return settings }

        var cleaned = hooks
        for pair in hooks.objectPairs ?? [] {
            cleaned = cleaned.setting(pair.key, to: pruned(stripped(pair.value)))
        }
        // An empty "hooks" object is not information, and leaving it behind on
        // a machine where we created it would show up in that same diff.
        let remaining = cleaned.objectPairs ?? []
        return settings.setting("hooks", to: remaining.isEmpty ? nil : cleaned)
    }

    // MARK: - Entries

    /// `{"type":"command","command":"…/vibe-hook","vibebuddy":"1"}`
    static func entry(hookPath: String) -> OrderedJSON {
        .object([
            ("type", .string("command")),
            ("command", .string(hookPath)),
            (markerKey, .string(markerValue)),
        ])
    }

    /// A matcher on every event, including those where Claude Code ignores it.
    /// Uniform beats conditional here: one shape to write, one to recognise.
    static func group(hookPath: String) -> OrderedJSON {
        .object([
            ("matcher", .string("*")),
            ("hooks", .array([entry(hookPath: hookPath)])),
        ])
    }

    public static func isOurs(_ entry: OrderedJSON) -> Bool {
        if case .string = entry[markerKey] { return true }
        // Marker lost to a hand edit, or written by a version that predates it:
        // still ours, and still ours to clean up.
        if case let .string(command)? = entry["command"] {
            return (command as NSString).lastPathComponent == executableName
        }
        return false
    }

    // MARK: - Rewriting one event's array

    /// Puts our entry in `array` exactly once, **in place** when one is already
    /// there. Appending a fresh group every time would move it to the end on
    /// the first run and duplicate it on every run after that.
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
