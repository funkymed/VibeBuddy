import Foundation
import Testing
@testable import VibeBuddyKit

@Suite("Granting a rule for good")
struct PermissionRulesTests {

    static let userFile = """
    {
      "$schema": "https://json.schemastore.org/claude-code-settings.json",
      "permissions": {
        "allow": ["Read", "Bash(git status:*)"],
        "deny": ["Bash(rm -rf /:*)"]
      },
      "model": "opus[1m]"
    }
    """

    static func parsed(_ text: String) throws -> OrderedJSON {
        try OrderedJSON.parse(Data(text.utf8))
    }

    /// A writer pointed at a throwaway file, and the rules that use it.
    static func onDisk(_ contents: String? = userFile) throws
        -> (rules: PermissionRules, path: String, directory: String) {
        let directory = NSTemporaryDirectory() + "rules-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/settings.json"
        if let contents { try Data(contents.utf8).write(to: URL(fileURLWithPath: path)) }
        ClaudeSettingsWriter.forgetBackupForTesting()
        return (PermissionRules(writer: ClaudeSettingsWriter(
            path: path, backupDirectory: directory + "/backups")), path, directory)
    }

    // MARK: - Reading

    @Test("what is granted is read as written")
    func readsGranted() throws {
        let (rules, _, directory) = try Self.onDisk()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(rules.granted() == ["Read", "Bash(git status:*)"])
    }

    // Failing to *grant* is safe; the caller is a permission prompt that has to
    // work whatever state the file is in.
    @Test("a file that is missing or broken grants nothing, rather than throwing")
    func unreadableGrantsNothing() throws {
        let (missing, _, dir1) = try Self.onDisk(nil)
        defer { try? FileManager.default.removeItem(atPath: dir1) }
        #expect(missing.granted().isEmpty)

        let (broken, path, dir2) = try Self.onDisk("{ pas du json")
        defer { try? FileManager.default.removeItem(atPath: dir2) }
        #expect(broken.granted().isEmpty)
        // And it is still there, untouched.
        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Adding, as a pure value

    @Test("a rule is appended, and everything else keeps its place")
    func appendsInPlace() throws {
        let before = try Self.parsed(Self.userFile)
        let after = PermissionRules.adding("Bash(npm test:*)", to: before)

        #expect(try #require(after.objectPairs).map(\.key) == ["$schema", "permissions", "model"])
        guard case let .array(rules)? = after["permissions"]?["allow"] else {
            Issue.record("allow perdu"); return
        }
        #expect(rules == [.string("Read"), .string("Bash(git status:*)"),
                          .string("Bash(npm test:*)")])
        // `deny` is not ours to touch.
        #expect(after["permissions"]?["deny"] == before["permissions"]?["deny"])
    }

    @Test("a rule already there changes nothing at all")
    func idempotent() throws {
        let before = try Self.parsed(Self.userFile)
        #expect(PermissionRules.adding("Read", to: before) == before)
    }

    @Test("a file with no permissions block grows one")
    func createsTheBlock() throws {
        let bare = try Self.parsed(#"{ "model": "opus" }"#)
        let after = PermissionRules.adding("Bash", to: bare)
        #expect(after["permissions"]?["allow"] == .array([.string("Bash")]))
        // The user's own key stays first.
        #expect(try #require(after.objectPairs).first?.key == "model")
    }

    // The file is the user's. Anything we do not understand is left alone
    // rather than reinterpreted.
    @Test("a permissions block of an unexpected shape is left exactly as it was",
          arguments: [#"{ "permissions": "off" }"#, #"{ "permissions": { "allow": "tout" } }"#])
    func refusesOddShapes(_ text: String) throws {
        let odd = try Self.parsed(text)
        #expect(PermissionRules.adding("Bash", to: odd) == odd)
    }

    // MARK: - The rule offered

    // Claude Code's suggestion is scoped to what was actually asked; the bare
    // tool name grants every use of it for ever.
    @Test("Claude Code's own suggestion is preferred to the tool's name")
    func prefersTheSuggestion() {
        let model = PermissionRequestModel(
            id: "a", toolName: "Bash", summary: .shell(command: "npm test", description: nil),
            suggestions: ["Bash(npm test:*)"])
        #expect(PermissionRules.rule(for: model) == "Bash(npm test:*)")
    }

    @Test("with no suggestion, the tool's bare name is the fallback")
    func fallsBackToTheToolName() {
        let model = PermissionRequestModel(
            id: "a", toolName: "WebFetch", summary: .url("https://x.invalid"))
        #expect(PermissionRules.rule(for: model) == "WebFetch")
    }

    // MARK: - Writing, and the consent that must come first

    @Test("committing writes once, and says so; a second time writes nothing")
    func commitIsIdempotent() throws {
        let (rules, path, directory) = try Self.onDisk()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        #expect(try rules.commit(adding: "Bash(npm test:*)") == true)
        #expect(try rules.commit(adding: "Bash(npm test:*)") == false)
        #expect(rules.granted().contains("Bash(npm test:*)"))

        // Everything the user had is still there.
        let final = try OrderedJSON.parse(
            #require(FileManager.default.contents(atPath: path)))
        #expect(final["model"] == .string("opus[1m]"))
        #expect(final["permissions"]?["deny"] == .array([.string("Bash(rm -rf /:*)")]))
    }

    @Test("the first write leaves a backup, because that is what makes it undoable")
    func commitBacksUp() throws {
        let (rules, _, directory) = try Self.onDisk()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(try rules.commit(adding: "Bash") == true)
        let backups = (try? FileManager.default.contentsOfDirectory(
            atPath: directory + "/backups")) ?? []
        #expect(backups.count == 1)
    }

    // T8's whole point: the diff is shown before anything is written.
    @Test("a consent carries the diff, and nothing has been written yet")
    func consentShowsTheDiffWithoutWriting() throws {
        let (rules, path, directory) = try Self.onDisk()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let untouched = try String(contentsOfFile: path, encoding: .utf8)

        let model = PermissionRequestModel(
            id: "a", toolName: "Bash", summary: .shell(command: "npm test", description: nil),
            suggestions: ["Bash(npm test:*)"])
        let consent = try #require(PermissionConsent.make(for: model, rules: rules))

        #expect(consent.rule == "Bash(npm test:*)")
        #expect(consent.diff.contains("Bash(npm test:*)"))
        #expect(consent.diff.contains("+"))
        // The file has not moved.
        #expect(try String(contentsOfFile: path, encoding: .utf8) == untouched)
    }

    @Test("nothing to write means nothing to consent to")
    func noConsentWhenAlreadyGranted() throws {
        let (rules, _, directory) = try Self.onDisk()
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let model = PermissionRequestModel(
            id: "a", toolName: "Read", summary: .read(path: "/etc/hosts"))
        #expect(PermissionConsent.make(for: model, rules: rules) == nil)
    }
}
