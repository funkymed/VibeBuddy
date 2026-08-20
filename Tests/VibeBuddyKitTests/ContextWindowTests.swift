import Foundation
import Testing
@testable import VibeBuddyKit

/// The window is a fact about the configuration, not about the transcript.
///
/// Measured on the machine this was written on: `~/.claude/settings.json` holds
/// `"model": "opus[1m]"`, and every assistant entry of the matching transcript
/// says plain `claude-opus-5`. Reading the tokens tells you nothing about what
/// they are a fraction *of*.
@Suite("Context window")
struct ContextWindowTests {

    /// A throwaway home and project, so the test never reads the developer's
    /// own settings — which is exactly how this bug survived: on a machine
    /// configured for 1M, a hard-coded 200k looks right until you divide.
    private func sandbox() throws -> (home: String, project: String) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ctxwin-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let project = root.appendingPathComponent("project")
        for dir in [home, project] {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        }
        return (home.path, project.path)
    }

    private func write(_ json: String, to path: String) throws {
        try json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test("no settings at all means the default window")
    func noSettings() throws {
        let (home, project) = try sandbox()
        var resolver = ContextWindowResolver(home: home)
        #expect(resolver.window(forProject: project) == 200_000)
    }

    @Test("the user's model marker selects the large window")
    func userSettingsMarker() throws {
        let (home, project) = try sandbox()
        try write(#"{"model":"opus[1m]"}"#, to: home + "/.claude/settings.json")
        var resolver = ContextWindowResolver(home: home)
        #expect(resolver.window(forProject: project) == 1_000_000)
    }

    @Test("a model without the marker stays at the default")
    func plainModel() throws {
        let (home, project) = try sandbox()
        try write(#"{"model":"claude-opus-5"}"#, to: home + "/.claude/settings.json")
        var resolver = ContextWindowResolver(home: home)
        #expect(resolver.window(forProject: project) == 200_000)
    }

    // Claude Code's own precedence: the project's local file has the last word.
    @Test("the project overrides the user, and local overrides the project")
    func precedence() throws {
        let (home, project) = try sandbox()
        try write(#"{"model":"opus[1m]"}"#, to: home + "/.claude/settings.json")
        try write(#"{"model":"claude-sonnet-5"}"#, to: project + "/.claude/settings.json")
        var resolver = ContextWindowResolver(home: home)
        #expect(resolver.window(forProject: project) == 200_000)

        try write(#"{"model":"sonnet[1m]"}"#, to: project + "/.claude/settings.local.json")
        var second = ContextWindowResolver(home: home)
        #expect(second.window(forProject: project) == 1_000_000)
    }

    @Test("ANTHROPIC_MODEL counts as naming a model")
    func envModel() throws {
        let (home, project) = try sandbox()
        try write(#"{"env":{"ANTHROPIC_MODEL":"opus[1m]"}}"#, to: home + "/.claude/settings.json")
        var resolver = ContextWindowResolver(home: home)
        #expect(resolver.window(forProject: project) == 1_000_000)
    }

    // Unreadable settings must never take the app down, and must never invent a
    // window either: the default is the honest answer.
    @Test("malformed settings fall back to the default")
    func malformed() throws {
        let (home, project) = try sandbox()
        try write("{ not json", to: home + "/.claude/settings.json")
        var resolver = ContextWindowResolver(home: home)
        #expect(resolver.window(forProject: project) == 200_000)
    }

    @Test("a settings change is picked up, a stable file is not re-parsed")
    func cacheFollowsMtime() throws {
        let (home, project) = try sandbox()
        let path = home + "/.claude/settings.json"
        try write(#"{"model":"claude-opus-5"}"#, to: path)
        var resolver = ContextWindowResolver(home: home)
        #expect(resolver.window(forProject: project) == 200_000)
        #expect(resolver.window(forProject: project) == 200_000)   // served from cache

        try write(#"{"model":"opus[1m]"}"#, to: path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: path)
        #expect(resolver.window(forProject: project) == 1_000_000)
    }

    @Test("the marker is read on the name, whatever the family")
    func markerOnly() {
        #expect(ContextWindowResolver.window(forModel: "opus[1m]") == 1_000_000)
        #expect(ContextWindowResolver.window(forModel: "claude-sonnet-5[1M]") == 1_000_000)
        #expect(ContextWindowResolver.window(forModel: "claude-opus-5") == 200_000)
        #expect(ContextWindowResolver.window(forModel: "") == 200_000)
    }
}
