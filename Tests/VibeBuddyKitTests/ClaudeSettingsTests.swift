import Foundation
import Testing
@testable import VibeBuddyKit

@Suite("JSON that keeps its order")
struct OrderedJSONTests {
    static let document = """
    {
      "$schema": "https://example.invalid/schema.json",
      "env": { "A": "1", "B": "2" },
      "model": "opus",
      "hooks": { "Stop": [] },
      "verbose": false,
      "ratio": 1.0,
      "big": 12345678901234567890,
      "nothing": null,
      "list": [1, "deux", true]
    }
    """

    @Test("the order of the keys survives a round trip")
    func orderSurvives() throws {
        let parsed = try OrderedJSON.parse(Data(Self.document.utf8))
        let keys = try #require(parsed.objectPairs).map(\.key)
        #expect(keys == ["$schema", "env", "model", "hooks", "verbose", "ratio",
                         "big", "nothing", "list"])
        // `$schema` first is the whole point: a dictionary would put it anywhere.
        let again = try OrderedJSON.parse(Data(parsed.encoded().utf8))
        #expect(again == parsed)
        #expect(try #require(again.objectPairs).map(\.key) == keys)
    }

    /// `JSONSerialization` turns `1.0` into `1` and loses digits off a large integer.
    @Test("numbers keep the text they were written with")
    func numbersKeepTheirLiteral() throws {
        let parsed = try OrderedJSON.parse(Data(Self.document.utf8))
        #expect(parsed["ratio"] == .number("1.0"))
        #expect(parsed["big"] == .number("12345678901234567890"))
        #expect(parsed.encoded().contains("\"ratio\": 1.0"))
    }

    @Test("replacing a key leaves it where it was")
    func settingKeepsPosition() throws {
        let parsed = try OrderedJSON.parse(Data(Self.document.utf8))
        let updated = parsed.setting("model", to: .string("sonnet"))
        #expect(try #require(updated.objectPairs).map(\.key)
                == (try #require(parsed.objectPairs).map(\.key)))
        #expect(updated["model"] == .string("sonnet"))
    }

    @Test("a new key goes to the end, and removing one takes it out")
    func settingAppendsAndRemoves() throws {
        let parsed = try OrderedJSON.parse(Data(Self.document.utf8))
        let added = parsed.setting("nouveau", to: .bool(true))
        #expect(try #require(added.objectPairs).last?.key == "nouveau")
        let removed = added.setting("nouveau", to: nil)
        #expect(removed == parsed)
    }

    @Test("escapes and non-ASCII survive", arguments: [
        #"{"a":"guillemet \" et \\ et \n"}"#,
        #"{"a":"accentué : é à ü"}"#,
        #"{"a":"emoji 😀"}"#,
        #"{"a":"tabulation \t fin"}"#,
    ])
    func escapesSurvive(_ text: String) throws {
        let parsed = try OrderedJSON.parse(Data(text.utf8))
        let again = try OrderedJSON.parse(Data(parsed.encoded().utf8))
        #expect(again == parsed)
    }

    @Test("nonsense is refused rather than half-parsed", arguments: [
        "", "{", "{\"a\"}", "{\"a\":}", "[1,]", "{\"a\":1}trailing", "{'a':1}",
    ])
    func rejectsJunk(_ text: String) {
        #expect(throws: (any Error).self) { try OrderedJSON.parse(Data(text.utf8)) }
    }

    /// The real thing, when it is there.
    @Test("the user's own settings.json round-trips unchanged")
    func realFileRoundTrips() throws {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/settings.json")
        guard let data = FileManager.default.contents(atPath: path) else { return }
        let parsed = try OrderedJSON.parse(data)
        let again = try OrderedJSON.parse(Data(parsed.encoded().utf8))
        #expect(again == parsed)
        // Every key still where the user put it.
        let before = try #require(parsed.objectPairs).map(\.key)
        let after = try #require(again.objectPairs).map(\.key)
        #expect(before == after)
    }
}

@Suite("Writing the user's settings")
struct ClaudeSettingsWriterTests {
    private func scratch() -> (writer: ClaudeSettingsWriter, path: String, backups: String) {
        let root = NSTemporaryDirectory() + "vb-settings-\(UUID().uuidString)"
        let path = root + "/settings.json"
        let backups = root + "/backups"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        ClaudeSettingsWriter.forgetBackupForTesting()
        return (ClaudeSettingsWriter(path: path, backupDirectory: backups), path, backups)
    }

    @Test("a missing file reads as an empty object, so a fresh machine works")
    func missingFileIsEmpty() throws {
        let (writer, _, _) = scratch()
        #expect(try writer.read() == .object([]))
    }

    @Test("a mutation preserves every key the app knows nothing about")
    func foreignKeysSurvive() throws {
        let (writer, path, _) = scratch()
        let original = """
        {
          "$schema": "x",
          "inconnu": { "profond": [1, 2] },
          "model": "opus"
        }
        """
        try Data(original.utf8).write(to: URL(fileURLWithPath: path))

        #expect(try writer.mutate { $0.setting("hooks", to: .object([])) })
        let after = try writer.read()
        #expect(try #require(after.objectPairs).map(\.key) == ["$schema", "inconnu", "model", "hooks"])
        #expect(after["inconnu"] == .object([("profond", .array([.number("1"), .number("2")]))]))
    }

    @Test("the first write leaves a backup")
    func firstWriteBacksUp() throws {
        let (writer, path, backups) = scratch()
        try Data(#"{"model":"opus"}"#.utf8).write(to: URL(fileURLWithPath: path))
        try writer.mutate { $0.setting("hooks", to: .object([])) }
        let saved = try FileManager.default.contentsOfDirectory(atPath: backups)
        #expect(saved.count == 1, "\(saved)")
        let text = try String(
            contentsOfFile: backups + "/" + #require(saved.first), encoding: .utf8)
        #expect(text == #"{"model":"opus"}"#, "la sauvegarde est l'original, pas le résultat")
    }

    /// A hundred backups of the same file is a haystack, not a safety net.
    @Test("later writes in the same run do not pile up backups")
    func oneBackupPerRun() throws {
        let (writer, path, backups) = scratch()
        try Data(#"{"model":"opus"}"#.utf8).write(to: URL(fileURLWithPath: path))
        try writer.mutate { $0.setting("a", to: .bool(true)) }
        try writer.mutate { $0.setting("b", to: .bool(true)) }
        try writer.mutate { $0.setting("c", to: .bool(true)) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups).count == 1)
    }

    /// An install that is already correct must not touch the file.
    @Test("a change that changes nothing writes nothing")
    func noOpDoesNotWrite() throws {
        let (writer, path, backups) = scratch()
        try Data(#"{"model":"opus"}"#.utf8).write(to: URL(fileURLWithPath: path))
        let before = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date

        #expect(try writer.mutate { _ in nil } == false)
        #expect(try writer.mutate { $0 } == false)
        #expect(try writer.mutate { $0.setting("model", to: .string("opus")) } == false)

        let after = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        #expect(before == after)
        #expect(!FileManager.default.fileExists(atPath: backups))
    }

    @Test("each mutation re-reads, so an edit made meanwhile is not reverted")
    func rereadsBeforeWriting() throws {
        let (writer, path, _) = scratch()
        try Data(#"{"a":"1"}"#.utf8).write(to: URL(fileURLWithPath: path))
        try writer.mutate { $0.setting("b", to: .string("2")) }
        // The user edits the file behind our back.
        try Data(#"{"a":"1","b":"2","c":"3"}"#.utf8).write(to: URL(fileURLWithPath: path))
        try writer.mutate { $0.setting("d", to: .string("4")) }
        let after = try writer.read()
        #expect(after["c"] == .string("3"), "l'édition de l'utilisateur a été écrasée")
        #expect(after["d"] == .string("4"))
    }

    @Test("an unreadable file is refused rather than overwritten")
    func refusesToClobberGarbage() throws {
        let (writer, path, _) = scratch()
        try Data("ceci n'est pas du json".utf8).write(to: URL(fileURLWithPath: path))
        #expect(throws: (any Error).self) { try writer.read() }
        #expect(throws: (any Error).self) {
            try writer.mutate { $0.setting("hooks", to: .object([])) }
        }
        let untouched = try String(contentsOfFile: path, encoding: .utf8)
        #expect(untouched == "ceci n'est pas du json")
    }

    @Test("a JSON file that is not an object is refused too")
    func refusesNonObject() throws {
        let (writer, path, _) = scratch()
        try Data("[1,2,3]".utf8).write(to: URL(fileURLWithPath: path))
        #expect(throws: ClaudeSettingsWriter.Failure.notAnObject) { try writer.read() }
    }
}
