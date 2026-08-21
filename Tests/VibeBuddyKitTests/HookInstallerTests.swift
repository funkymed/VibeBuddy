import Foundation
import Testing
import VibeHookProtocol
@testable import VibeBuddyKit

@Suite("Installing the hook")
struct HookInstallerTests {

    /// A settings file with keys we must not touch, in an order we must not
    /// change, and a hook of the user's own.
    static let userFile = """
    {
      "$schema": "https://json.schemastore.org/claude-code-settings.json",
      "model": "opus[1m]",
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              { "type": "command", "command": "/usr/local/bin/mine.sh" }
            ]
          }
        ]
      },
      "verbose": false
    }
    """

    static func parsed(_ text: String) throws -> OrderedJSON {
        try OrderedJSON.parse(Data(text.utf8))
    }

    // MARK: - Installing

    @Test("every event we register ends up in the file")
    func registersEveryEvent() throws {
        let after = HookInstaller.installing(try Self.parsed(Self.userFile), hookPath: "/A/vibe-hook")
        let hooks = try #require(after["hooks"])
        for event in HookEventName.allCases {
            let groups = try #require(hooks[event.rawValue])
            guard case let .array(list) = groups else { Issue.record("\(event) absent"); continue }
            let ours = list.contains { group in
                guard case let .array(inner)? = group["hooks"] else { return false }
                return inner.contains { HookInstaller.isOurs($0) }
            }
            #expect(ours, "\(event.rawValue) n'a pas notre entrée")
        }
    }

    @Test("a second install changes nothing at all")
    func idempotent() throws {
        let once = HookInstaller.installing(try Self.parsed(Self.userFile), hookPath: "/A/vibe-hook")
        let twice = HookInstaller.installing(once, hookPath: "/A/vibe-hook")
        #expect(twice == once)
        // Byte-for-byte, not just structurally equal: `mutate` compares values,
        // but what lands on disk is the encoding.
        #expect(twice.encoded() == once.encoded())
    }

    @Test("the user's own keys, order and hooks survive")
    func leavesTheUserAlone() throws {
        let before = try Self.parsed(Self.userFile)
        let after = HookInstaller.installing(before, hookPath: "/A/vibe-hook")

        #expect(try #require(after.objectPairs).map(\.key)
            == ["$schema", "model", "hooks", "verbose"])
        #expect(after["model"] == before["model"])
        #expect(after["verbose"] == before["verbose"])

        // Their PreToolUse hook is still there, in its own group, untouched.
        guard case let .array(groups)? = after["hooks"]?["PreToolUse"] else {
            Issue.record("PreToolUse perdu"); return
        }
        let theirs = groups.first { $0["matcher"] == .string("Bash") }
        #expect(theirs?["hooks"] == .array([
            .object([("type", .string("command")), ("command", .string("/usr/local/bin/mine.sh"))])
        ]))
    }

    @Test("moving the app rewrites the entry in place instead of adding one")
    func staleaPathIsReplaced() throws {
        let installed = HookInstaller.installing(try Self.parsed(Self.userFile), hookPath: "/old/vibe-hook")
        let moved = HookInstaller.installing(installed, hookPath: "/new/vibe-hook")

        guard case let .array(groups)? = moved["hooks"]?["Stop"] else {
            Issue.record("Stop perdu"); return
        }
        let entries = groups.flatMap { group -> [OrderedJSON] in
            guard case let .array(inner)? = group["hooks"] else { return [] }
            return inner
        }
        #expect(entries.filter { HookInstaller.isOurs($0) }.count == 1)
        #expect(entries.first?["command"] == .string("/new/vibe-hook"))
    }

    @Test("an event we no longer register loses our entry and its key")
    func obsoleteEventIsCleanedUp() throws {
        let withObsolete = """
        {
          "hooks": {
            "PreCompact": [
              { "hooks": [ { "type": "command", "command": "/A/vibe-hook", "vibebuddy": "1" } ] }
            ]
          }
        }
        """
        let after = HookInstaller.installing(try Self.parsed(withObsolete), hookPath: "/A/vibe-hook")
        #expect(after["hooks"]?["PreCompact"] == nil)
    }

    @Test("an obsolete event that also holds a hook of theirs keeps theirs")
    func obsoleteEventKeepsTheirs() throws {
        let mixed = """
        {
          "hooks": {
            "PreCompact": [
              { "hooks": [
                { "type": "command", "command": "/A/vibe-hook", "vibebuddy": "1" },
                { "type": "command", "command": "/usr/local/bin/mine.sh" }
              ] }
            ]
          }
        }
        """
        let after = HookInstaller.installing(try Self.parsed(mixed), hookPath: "/A/vibe-hook")
        guard case let .array(groups)? = after["hooks"]?["PreCompact"],
              case let .array(inner)? = groups.first?["hooks"]
        else { Issue.record("PreCompact perdu"); return }
        #expect(inner.count == 1)
        #expect(inner.first?["command"] == .string("/usr/local/bin/mine.sh"))
    }

    /// The marker is what makes an entry ours. A path is not enough — the app
    /// moves — but a hand edit can drop the marker, and the entry is still ours.
    @Test("an entry is recognised by its marker, or failing that by its name")
    func recognisesOurEntries() {
        #expect(HookInstaller.isOurs(.object([
            ("type", .string("command")), ("command", .string("/wherever/vibe-hook")),
            ("vibebuddy", .string("1")),
        ])))
        #expect(HookInstaller.isOurs(.object([("command", .string("/moved/vibe-hook"))])))
        #expect(!HookInstaller.isOurs(.object([("command", .string("/usr/local/bin/mine.sh"))])))
        #expect(!HookInstaller.isOurs(.object([("command", .string("/opt/vibe-hook-wrapper"))])))
    }

    // MARK: - Uninstalling

    @Test("uninstalling leaves exactly what was there before installing")
    func uninstallIsTheInverse() throws {
        let before = try Self.parsed(Self.userFile)
        let installed = HookInstaller.installing(before, hookPath: "/A/vibe-hook")
        #expect(installed != before)
        let removed = HookInstaller.removing(installed)
        // The exit criterion of T9, expressed the way the criterion is worded:
        // a diff against the file we started from is empty.
        #expect(removed.encoded() == before.encoded())
    }

    @Test("on a machine with no hooks at all, uninstalling leaves no residue")
    func uninstallLeavesNoEmptyHooks() throws {
        let bare = try Self.parsed("""
        { "$schema": "x", "model": "opus" }
        """)
        let installed = HookInstaller.installing(bare, hookPath: "/A/vibe-hook")
        #expect(installed["hooks"] != nil)
        let removed = HookInstaller.removing(installed)
        #expect(removed["hooks"] == nil)
        #expect(removed.encoded() == bare.encoded())
    }

    @Test("uninstalling touches nothing of the user's")
    func uninstallKeepsTheirHooks() throws {
        let before = try Self.parsed(Self.userFile)
        let removed = HookInstaller.removing(HookInstaller.installing(before, hookPath: "/A/vibe-hook"))
        guard case let .array(groups)? = removed["hooks"]?["PreToolUse"] else {
            Issue.record("leur hook a disparu"); return
        }
        #expect(groups.count == 1)
        #expect(groups.first?["matcher"] == .string("Bash"))
    }

    @Test("uninstalling a file that never had us changes nothing")
    func uninstallOnCleanFile() throws {
        let before = try Self.parsed(Self.userFile)
        #expect(HookInstaller.removing(before) == before)
    }

    // MARK: - Refusals

    /// The file is the user's. Anything we do not understand is left alone
    /// rather than reinterpreted — that is what keeps a wrong guess from
    /// becoming a wrong write.
    @Test("a \"hooks\" key that is not an object is left alone")
    func refusesNonObjectHooks() throws {
        let odd = try Self.parsed(#"{ "hooks": "off" }"#)
        #expect(HookInstaller.installing(odd, hookPath: "/A/vibe-hook") == odd)
        #expect(HookInstaller.removing(odd) == odd)
    }

    @Test("an event whose value is not an array is left alone")
    func refusesNonArrayEvent() throws {
        let odd = try Self.parsed(#"{ "hooks": { "Stop": "nope" } }"#)
        let after = HookInstaller.installing(odd, hookPath: "/A/vibe-hook")
        #expect(after["hooks"]?["Stop"] == .string("nope"))
    }

    // MARK: - Through the writer, on a real file

    @Test("installing writes once and then leaves the file's date alone")
    func writesOnceThroughTheWriter() throws {
        let directory = NSTemporaryDirectory() + "hookinstaller-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/settings.json"
        try Data(Self.userFile.utf8).write(to: URL(fileURLWithPath: path))

        ClaudeSettingsWriter.forgetBackupForTesting()
        let installer = HookInstaller(
            hookPath: "/A/vibe-hook",
            writer: ClaudeSettingsWriter(path: path, backupDirectory: directory + "/backups"))

        #expect(try installer.install() == true)
        #expect(try installer.install() == false)   // idempotent, nothing written
        #expect(try installer.uninstall() == true)
        #expect(try installer.uninstall() == false)

        // And what is on disk is what we started from: same keys, same order,
        // same values. Not the same bytes — the writer re-serialises with one
        // key per line, so an object the user had written inline comes back
        // expanded. Order is what D6 protects; layout is not.
        let final = try OrderedJSON.parse(
            #require(FileManager.default.contents(atPath: path)))
        #expect(final == (try Self.parsed(Self.userFile)))
    }
}
