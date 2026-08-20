import AppKit
import Foundation

/// Matched on the tty (see `ProcessLookup.tty`), never on title or cwd.
/// Under tmux the agent's tty is the pane's, not the emulator's, so no iTerm2 session
/// carries it: the match fails and the fallback activates the app without a tab.
/// See RFC-003, « Notes d'implémentation ».
public enum TerminalJumper {

    public enum Outcome: Sendable, Equatable {
        case selectedTab(app: String)
        case activatedApp(app: String)
        case noTerminal
        case failed(String)
    }

    /// Emulators that publish a tty and can select a tab. Ghostty, kitty and Alacritty
    /// ship no scripting dictionary and must fall back to activation.
    static let scriptable: Set<String> = ["iTerm2", "iTerm", "Terminal"]

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
            // No tab owns this tty — tmux, or a session that outlived its tab.
            app?.activate()
            return .activatedApp(app: name)
        case let .error(message):
            return .failed(message)
        }
    }

    public static func canSelectTab(agentPID: pid_t) -> Bool {
        guard let terminal = TerminalFocusProbe.hostingTerminal(of: agentPID),
              let name = ProcessLookup.name(of: terminal)
        else { return false }
        return scriptable.contains(name) && ProcessLookup.tty(of: agentPID) != nil
    }

    // MARK: - Scripts

    /// iTerm2 nests windows > tabs > sessions, with the tty on the session. Select all
    /// three, outermost first: selecting the session alone does not order the window.
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

    /// Errors are values: a refused automation prompt is the common case and must reach
    /// the user as a sentence, not a silent no-op.
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
