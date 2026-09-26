import Foundation

/// Where `~/.claude/settings.json` stands with respect to our hook.
public enum HookInstallState: Equatable, Sendable {
    /// Every event registered, pointing at this app's `vibe-hook`.
    case installed
    /// Nothing of ours in the file.
    case missing
    /// Entries of ours pointing somewhere else: the app moved, or a dev build wrote them.
    case stale(path: String)
    /// Entries of ours, at the right path, but not for every event.
    case partial
    /// The file cannot be parsed. Nothing gets written to it.
    case unreadable(String)

    /// What a click would do: install, repair, remove — or nothing.
    public var needsInstall: Bool {
        switch self {
        case .missing, .stale, .partial: return true
        case .installed, .unreadable: return false
        }
    }
}

/// What the settings pane shows, read in one go.
public struct HookInstallReport: Equatable, Sendable {
    public let state: HookInstallState
    /// `permissions.defaultMode: "auto"` asks nothing, so the hook never fires. Said,
    /// never changed: that setting is not ours.
    public let asksNothing: Bool

    public init(state: HookInstallState, asksNothing: Bool) {
        self.state = state
        self.asksNothing = asksNothing
    }
}

extension HookInstaller {
    /// Pure: the same comparison the CLI makes, so « installed » means « nothing to
    /// write » in both places.
    public static func state(of settings: OrderedJSON, hookPath: String) -> HookInstallState {
        let ours = ourCommands(in: settings)
        guard !ours.isEmpty else { return .missing }
        if installing(settings, hookPath: hookPath) == settings { return .installed }
        if let elsewhere = ours.first(where: { $0 != hookPath }) { return .stale(path: elsewhere) }
        return .partial
    }

    public static func asksNothing(_ settings: OrderedJSON) -> Bool {
        if case .string("auto")? = settings["permissions"]?["defaultMode"] { return true }
        return false
    }

    /// Reads the file now. Blocking: call it off the main thread.
    public func inspect() -> HookInstallReport {
        do {
            let settings = try writer.read()
            return HookInstallReport(
                state: Self.state(of: settings, hookPath: hookPath),
                asksNothing: Self.asksNothing(settings))
        } catch {
            return HookInstallReport(state: .unreadable("\(error)"), asksNothing: false)
        }
    }

    /// The diff a click would write, from the file as it is right now. Nil when there
    /// is nothing to write.
    public func pendingDiff(removing: Bool) throws -> (before: OrderedJSON, after: OrderedJSON)? {
        let before = try writer.read()
        let after = removing ? Self.removing(before) : preview(before)
        return after == before ? nil : (before, after)
    }

    /// The command of every entry of ours, in file order.
    static func ourCommands(in settings: OrderedJSON) -> [String] {
        var out: [String] = []
        for pair in settings["hooks"]?.objectPairs ?? [] {
            guard case let .array(groups) = pair.value else { continue }
            for group in groups {
                guard case let .array(inner)? = group["hooks"] else { continue }
                for entry in inner where isOurs(entry) {
                    if case let .string(command)? = entry["command"] { out.append(command) }
                }
            }
        }
        return out
    }
}

/// Posted after the settings pane writes `settings.json`, so the panel re-reads it.
public extension Notification.Name {
    static let hookInstallChanged = Notification.Name("vibebuddy.hookInstallChanged")
}

/// The one-time notice in the panel: a live session, permissions that cannot reach us,
/// and nobody told yet.
public enum HookNotice {
    public static let seenKey = "vibebuddy.hook.noticeSeen"

    public static func shows(state: HookInstallState?, hasLiveSession: Bool, seen: Bool) -> Bool {
        guard hasLiveSession, !seen, let state else { return false }
        return state.needsInstall
    }
}
