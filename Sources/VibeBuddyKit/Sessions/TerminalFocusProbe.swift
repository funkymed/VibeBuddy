import AppKit
import Darwin

/// Under tmux the chain is `agent → shell → tmux server` and the server is detached
/// from whichever client displays it, so the answer degrades to "some terminal is
/// frontmost". Ambiguity errs toward *not* suppressing: a wrong suppression is worse
/// than a wrong alert. Why it lives here: see RFC-003, « Notes d'implémentation ».
public enum TerminalFocusProbe {

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

    public static let maxHops = 8

    /// `NSWorkspace` needs no permission, unlike the Accessibility queries ruled out for v1.
    @MainActor
    public static func isAnyTerminalFrontmost() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if let bundle = front.bundleIdentifier, terminalBundleIDs.contains(bundle) { return true }
        if let name = front.localizedName, terminalNames.contains(name) { return true }
        return false
    }

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

    /// Nil under tmux — the chain ends at the detached server.
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
