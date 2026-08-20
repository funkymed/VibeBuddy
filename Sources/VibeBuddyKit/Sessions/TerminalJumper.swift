import AppKit
import Foundation

/// Brings the terminal running a session to the front, on the right tab.
///
/// # The identity is the tty, and nothing else
///
/// Titles are set by shells and programs, and two agents in the same project
/// share a working directory — matching on either picks the wrong tab sooner or
/// later. Exactly one tab owns a given pty, and both iTerm2 and Terminal publish
/// it: `tty` is read-only on `session` in iTerm2's dictionary and on `tab` in
/// Terminal's. So this is an equality test, not a heuristic. R8 is about
/// pairing sessions with pids; it does not reappear here.
///
/// # What this does not do yet
///
/// **tmux.** Under tmux the agent's controlling terminal is the pane's pty, not
/// the emulator's, so no iTerm2 session carries it and the match fails. The
/// fallback then activates the application without selecting a tab, which is
/// honest — it is what `⌘Tab` would have done — rather than selecting a wrong
/// one. Asking tmux costs three subprocesses at click time and is RFC-008 T6.
///
/// # Cost
///
/// Nothing at rest. On a click: one `sysctl`, one parent-chain walk, and one
/// Apple Event. The event needs the automation permission, which macOS asks for
/// once, and only the first time someone clicks a row.
public enum TerminalJumper {

    /// What actually happened, so the caller can say so rather than guess.
    public enum Outcome: Sendable, Equatable {
        /// The tab hosting the session was selected and brought to the front.
        case selectedTab(app: String)
        /// The terminal was activated, but the tab could not be identified —
        /// tmux, or an emulator with no scripting dictionary.
        case activatedApp(app: String)
        /// No terminal could be found for this session at all.
        case noTerminal
        /// The scripting call failed, usually because permission was refused.
        case failed(String)
    }

    /// Emulators that publish a tty and can select a tab. Everything else falls
    /// back to activation — Ghostty, kitty and Alacritty ship no dictionary, and
    /// pretending otherwise would fail at the worst moment.
    static let scriptable: Set<String> = ["iTerm2", "iTerm", "Terminal"]

    /// Jump to the terminal hosting `agentPID`.
    ///
    /// Runs the Apple Event on the calling thread — callers do it off the main
    /// one, because a scripting round trip is milliseconds at best and blocks
    /// whatever thread it is on. The activation at the end is bounced back to
    /// the main actor by `NSRunningApplication`.
    public static func jump(agentPID: pid_t) -> Outcome {
        guard let terminal = TerminalFocusProbe.hostingTerminal(of: agentPID) else {
            return .noTerminal
        }
        let name = ProcessLookup.name(of: terminal) ?? ""
        let app = NSRunningApplication(processIdentifier: terminal)

        guard scriptable.contains(name), let tty = ProcessLookup.tty(of: agentPID) else {
            app?.activate()
            return app == nil ? .noTerminal : .activatedApp(app: name)
        }

        let script = name == "Terminal" ? terminalAppScript(tty: tty) : itermScript(tty: tty)
        switch run(script) {
        case .found:
            app?.activate()
            return .selectedTab(app: name)
        case .notFound:
            // The terminal is there but owns no tab with this tty — tmux, or a
            // session that outlived the tab it was started in.
            app?.activate()
            return .activatedApp(app: name)
        case let .error(message):
            return .failed(message)
        }
    }

    /// Whether a jump can do better than `⌘Tab` for this session, so the UI can
    /// avoid offering an action that will do nothing.
    public static func canSelectTab(agentPID: pid_t) -> Bool {
        guard let terminal = TerminalFocusProbe.hostingTerminal(of: agentPID),
              let name = ProcessLookup.name(of: terminal)
        else { return false }
        return scriptable.contains(name) && ProcessLookup.tty(of: agentPID) != nil
    }

    // MARK: - Scripts

    /// iTerm2: windows hold tabs hold sessions, and the tty is on the session.
    ///
    /// Selecting all three, outermost first, is what actually raises the window:
    /// selecting the session alone changes the tab without ordering the window
    /// forward.
    static func itermScript(tty: String) -> String {
        """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(tty)" then
                  select w
                  select t
                  select s
                  return "yes"
                end if
              end repeat
            end repeat
          end repeat
        end tell
        return "no"
        """
    }

    /// Terminal.app: no session class — the tty sits on the tab itself.
    static func terminalAppScript(tty: String) -> String {
        """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected tab of w to t
                set index of w to 1
                return "yes"
              end if
            end repeat
          end repeat
        end tell
        return "no"
        """
    }

    private enum ScriptResult {
        case found, notFound
        case error(String)
    }

    /// Run a script, saying whether it found its tab.
    ///
    /// Errors are values: a refused automation prompt is the common case, and it
    /// must reach the user as a sentence rather than as a silent no-op.
    private static func run(_ source: String) -> ScriptResult {
        guard let script = NSAppleScript(source: source) else { return .error("script illisible") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return .error((error[NSAppleScript.errorMessage] as? String) ?? "erreur inconnue")
        }
        return result.stringValue == "yes" ? .found : .notFound
    }
}
