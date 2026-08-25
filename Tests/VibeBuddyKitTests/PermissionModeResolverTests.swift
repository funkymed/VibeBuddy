import Testing
import Foundation
@testable import VibeBuddyKit

@Suite("Permission mode fallback")
struct PermissionModeResolverTests {
    private func sandbox() throws -> String {
        let root = NSTemporaryDirectory() + "vb-mode-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: root + "/.claude", withIntermediateDirectories: true)
        return root
    }

    private func write(_ json: String, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test("no settings anywhere leaves the mode empty rather than inventing one")
    func nothingDeclared() throws {
        let home = try sandbox(), project = try sandbox()
        var resolver = PermissionModeResolver(home: home)
        #expect(resolver.mode(forProject: project).isEmpty)
    }

    @Test("the user file supplies the mode")
    func fromHome() throws {
        let home = try sandbox(), project = try sandbox()
        try write(#"{"permissions":{"defaultMode":"auto"}}"#,
                  to: home + "/.claude/settings.json")
        var resolver = PermissionModeResolver(home: home)
        #expect(resolver.mode(forProject: project) == "auto")
    }

    // Measured, not assumed: `permissions.defaultMode` in the user file overrides both
    // `--settings` and `--permission-mode`, so it is what the session actually runs in.
    @Test("the user file wins over the project's")
    func homeWins() throws {
        let home = try sandbox(), project = try sandbox()
        try write(#"{"permissions":{"defaultMode":"auto"}}"#,
                  to: home + "/.claude/settings.json")
        try write(#"{"permissions":{"defaultMode":"plan"}}"#,
                  to: project + "/.claude/settings.json")
        var resolver = PermissionModeResolver(home: home)
        #expect(resolver.mode(forProject: project) == "auto")
    }

    @Test("a project mode is used when the user file has none")
    func projectOnly() throws {
        let home = try sandbox(), project = try sandbox()
        try write(#"{"permissions":{"defaultMode":"plan"}}"#,
                  to: project + "/.claude/settings.json")
        var resolver = PermissionModeResolver(home: home)
        #expect(resolver.mode(forProject: project) == "plan")
    }

    @Test("settings without a permissions block leave it empty")
    func noPermissionsBlock() throws {
        let home = try sandbox(), project = try sandbox()
        try write(#"{"model":"opus[1m]"}"#, to: home + "/.claude/settings.json")
        var resolver = PermissionModeResolver(home: home)
        #expect(resolver.mode(forProject: project).isEmpty)
    }

    @Test("unreadable JSON is not a mode")
    func brokenJSON() throws {
        let home = try sandbox(), project = try sandbox()
        try write("{ not json", to: home + "/.claude/settings.json")
        var resolver = PermissionModeResolver(home: home)
        #expect(resolver.mode(forProject: project).isEmpty)
    }

    @Test("a rewritten settings file is read again")
    func invalidates() throws {
        let home = try sandbox(), project = try sandbox()
        let path = home + "/.claude/settings.json"
        try write(#"{"permissions":{"defaultMode":"auto"}}"#, to: path)
        var resolver = PermissionModeResolver(home: home)
        #expect(resolver.mode(forProject: project) == "auto")

        // Same size, different content: the cache keys on mtime, so touch it forward.
        try write(#"{"permissions":{"defaultMode":"plan"}}"#, to: path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: path)
        #expect(resolver.mode(forProject: project) == "plan")
    }
}
