import Foundation
import Testing
@testable import VibeBuddyKit

/// The jump is an equality on the tty, so these tests check the two halves of that
/// equality: that the kernel side produces a `/dev/ttysNNN`, and that the script side
/// asks for exactly that string.
@Suite("Terminal jump")
struct TerminalJumperTests {
    @Test("launchd has no controlling terminal")
    func daemonHasNoTTY() {
        // pid 1 is the one process guaranteed to exist and guaranteed to have no tty,
        // which makes it the only portable negative case.
        #expect(ProcessLookup.tty(of: 1) == nil)
    }

    @Test("a tty, when there is one, is a device path")
    func ttyLooksLikeADevice() throws {
        // The test runner may or may not own a terminal — under `swift test` in a shell
        // it does, in CI it does not.
        guard let tty = ProcessLookup.tty(of: getpid()) else { return }
        #expect(tty.hasPrefix("/dev/tty"))
    }

    @Test("a pid with no terminal cannot select a tab")
    func noTerminalNoSelection() {
        #expect(TerminalJumper.canSelectTab(agentPID: 1) == false)
    }

    // The tty is interpolated into the script, and a mismatch here is a jump that
    // silently lands on the wrong tab — the one failure this design exists to rule out.
    @Test("the iTerm2 script matches on the session's tty")
    func itermScriptCarriesTTY() {
        let script = TerminalJumper.itermScript(tty: "/dev/ttys042")
        #expect(script.contains("tell application \"iTerm2\""))
        #expect(script.contains("if tty of s is \"/dev/ttys042\""))
        // Window, tab and session all get selected: selecting the session alone changes
        // tab without ordering the window forward.
        #expect(script.contains("select w"))
        #expect(script.contains("select t"))
        #expect(script.contains("select s"))
    }

    @Test("Terminal.app carries the tty on the tab, not on a session")
    func terminalAppScript() {
        let script = TerminalJumper.terminalAppScript(tty: "/dev/ttys007")
        #expect(script.contains("tell application \"Terminal\""))
        #expect(script.contains("if tty of t is \"/dev/ttys007\""))
        #expect(script.contains("set selected tab of w to t"))
        #expect(!script.contains("sessions of t"))   // Terminal has no session class
    }

    // Ghostty, kitty and Alacritty ship no scripting dictionary.
    @Test("only the emulators that publish a tty are scripted")
    func scriptableList() {
        #expect(TerminalJumper.scriptable.contains("iTerm2"))
        #expect(TerminalJumper.scriptable.contains("Terminal"))
        #expect(!TerminalJumper.scriptable.contains("Ghostty"))
        #expect(!TerminalJumper.scriptable.contains("kitty"))
    }
}
