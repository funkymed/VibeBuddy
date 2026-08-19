import AppKit
import Darwin

/// Answers one question: is the user already looking at this session?
///
/// It exists so RFC-007 can stay quiet. Interrupting someone with a permission
/// prompt in the notch while the very terminal asking for it is in front of them
/// is noise — they can see the question already.
///
/// # Where it lives, and why
///
/// This belongs to RFC-003, not to the session list that also wants it. Putting
/// it with the sessions view would make the permissions RFC depend on the
/// sessions RFC, which is a dependency cycle waiting to happen. It sits here
/// because this module already owns `ProcessLookup` and the PIDs.
///
/// # The tmux limitation, stated rather than hidden
///
/// Walking up from the agent's process normally reaches its terminal. Under
/// tmux it does not: the chain is `agent → shell → tmux server`, and the server
/// is detached from whichever client is displaying it. There is no way to tell
/// *which* terminal window shows a given pane without asking tmux, which costs
/// a subprocess — and this probe is consulted on every incoming permission.
///
/// So under tmux the answer degrades to "some terminal is frontmost", which is
/// the honest answer available for free. A wrong suppression is worse than a
/// wrong alert, so the ambiguous case errs toward *not* suppressing: it only
/// reports true when a terminal really is in front.
public enum TerminalFocusProbe {

    /// Executable names of terminal emulators, as `proc_name` reports them.
    /// Warp reports as `stable`, which is not a typo.
    public static let terminalNames: Set<String> = [
        "Terminal", "iTerm2", "iTerm", "Alacritty", "alacritty",
        "Ghostty", "ghostty", "kitty", "Warp", "stable",
        "WezTerm", "wezterm-gui", "Hyper", "Rio", "tabby", "Tabby",
    ]

    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "org.alacritty",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "dev.warp.Warp-Stable",
        "com.github.wez.wezterm", "co.zeit.hyper", "com.raphaelamorim.rio",
        "org.tabby",
    ]

    /// Maximum hops up the parent chain. Bounded because a chain can be long
    /// under nested shells, and because a cycle would otherwise hang the probe.
    public static let maxHops = 8

    /// Is a terminal application frontmost right now?
    ///
    /// Uses `NSWorkspace`, which needs no permission — unlike the Accessibility
    /// queries the reference implementation makes once a second, and which
    /// RFC-011 ruled out for v1.
    @MainActor
    public static func isAnyTerminalFrontmost() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if let bundle = front.bundleIdentifier, terminalBundleIDs.contains(bundle) { return true }
        if let name = front.localizedName, terminalNames.contains(name) { return true }
        return false
    }

    /// Is the terminal hosting `pid` the frontmost application?
    ///
    /// Returns false when it cannot be determined — under tmux, or when the
    /// chain runs out. Suppressing an alert wrongly is worse than showing one
    /// wrongly, so uncertainty resolves toward showing it.
    @MainActor
    public static func isHostingTerminalFrontmost(agentPID: pid_t) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        guard isAnyTerminalFrontmost() else { return false }

        let frontPID = front.processIdentifier
        var current = agentPID
        for _ in 0..<maxHops {
            guard let parent = ProcessLookup.parent(of: current), parent > 1 else { break }
            if parent == frontPID { return true }
            current = parent
        }
        return false
    }

    /// The terminal PID hosting `pid`, if the parent chain reaches one.
    ///
    /// Nil under tmux — the chain ends at the detached server. Callers that need
    /// certainty must ask tmux, which costs a subprocess; callers that only need
    /// a hint should use `isAnyTerminalFrontmost`.
    public static func hostingTerminal(of agentPID: pid_t) -> pid_t? {
        var current = agentPID
        for _ in 0..<maxHops {
            guard let parent = ProcessLookup.parent(of: current), parent > 1 else { return nil }
            if let name = ProcessLookup.name(of: parent), terminalNames.contains(name) {
                return parent
            }
            current = parent
        }
        return nil
    }
}
