import Foundation
import Testing
@testable import VibeBuddyKit

@Suite("What the settings pane says about the hook")
struct HookInstallStateTests {
    private func parsed(_ text: String) throws -> OrderedJSON {
        try OrderedJSON.parse(Data(text.utf8))
    }

    private var user: OrderedJSON { get throws { try parsed(HookInstallerTests.userFile) } }

    @Test("a file with nothing of ours is missing")
    func missing() throws {
        #expect(HookInstaller.state(of: try user, hookPath: "/A/vibe-hook") == .missing)
        #expect(HookInstaller.state(of: .object([]), hookPath: "/A/vibe-hook") == .missing)
    }

    @Test("installed means the CLI would have nothing to write")
    func installed() throws {
        let done = HookInstaller.installing(try user, hookPath: "/A/vibe-hook")
        #expect(HookInstaller.state(of: done, hookPath: "/A/vibe-hook") == .installed)
    }

    // The app moved, or a dev build installed it: the entries are ours, and Claude Code
    // calls a binary that is not the one running.
    @Test("entries of ours pointing elsewhere are stale, with the path")
    func stale() throws {
        let old = HookInstaller.installing(try user, hookPath: "/old/vibe-hook")
        #expect(HookInstaller.state(of: old, hookPath: "/new/vibe-hook") == .stale(path: "/old/vibe-hook"))
    }

    @Test("an event missing at the right path is partial")
    func partial() throws {
        let done = HookInstaller.installing(try user, hookPath: "/A/vibe-hook")
        let hooks = try #require(done["hooks"]).setting("Stop", to: nil)
        let cut = done.setting("hooks", to: hooks)
        #expect(HookInstaller.state(of: cut, hookPath: "/A/vibe-hook") == .partial)
    }

    @Test("only a stale, partial or missing hook asks for a click")
    func needsInstall() {
        #expect(HookInstallState.missing.needsInstall)
        #expect(HookInstallState.stale(path: "/x").needsInstall)
        #expect(HookInstallState.partial.needsInstall)
        #expect(!HookInstallState.installed.needsInstall)
        #expect(!HookInstallState.unreadable("x").needsInstall)
    }

    @Test("defaultMode auto is reported, anything else is not")
    func asksNothing() throws {
        #expect(HookInstaller.asksNothing(try parsed(#"{"permissions":{"defaultMode":"auto"}}"#)))
        #expect(!HookInstaller.asksNothing(try parsed(#"{"permissions":{"defaultMode":"default"}}"#)))
        #expect(!HookInstaller.asksNothing(try user))
    }

    @Test("an unparsable file is unreadable, and nothing is proposed")
    func unreadable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibebuddy-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try Data("{ not json".utf8).write(to: file)

        let installer = HookInstaller(hookPath: "/A/vibe-hook",
                                      writer: ClaudeSettingsWriter(path: file.path))
        guard case .unreadable = installer.inspect().state else {
            Issue.record("attendu : illisible"); return
        }
        #expect(throws: (any Error).self) { try installer.pendingDiff(removing: false) }
    }

    // The sheet shows what would be written from the file as it is now: an installed
    // hook has no install diff, a missing one no removal diff.
    @Test("the pending diff is nil when there is nothing to write")
    func pendingDiff() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibebuddy-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try Data(HookInstallerTests.userFile.utf8).write(to: file)
        let installer = HookInstaller(hookPath: "/A/vibe-hook",
                                      writer: ClaudeSettingsWriter(path: file.path))

        #expect(try installer.pendingDiff(removing: true) == nil)
        let install = try #require(try installer.pendingDiff(removing: false))
        #expect(HookInstaller.state(of: install.after, hookPath: "/A/vibe-hook") == .installed)
    }

    @Test("the notice shows once, with a live session, for a hook that needs a click")
    func notice() {
        #expect(HookNotice.shows(state: .missing, hasLiveSession: true, seen: false))
        #expect(HookNotice.shows(state: .stale(path: "/x"), hasLiveSession: true, seen: false))
        #expect(!HookNotice.shows(state: .missing, hasLiveSession: true, seen: true))
        #expect(!HookNotice.shows(state: .missing, hasLiveSession: false, seen: false))
        #expect(!HookNotice.shows(state: .installed, hasLiveSession: true, seen: false))
        #expect(!HookNotice.shows(state: nil, hasLiveSession: true, seen: false))
    }
}
