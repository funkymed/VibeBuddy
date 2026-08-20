import Foundation
import Testing
@testable import VibeBuddyKit

/// Moving a directory a user edits by hand deserves tests, because the failure
/// mode is not a crash: it is buddies that quietly stop existing.
@Suite("Support directory")
struct SupportDirectoryTests {

    private func sandbox() throws -> (old: String, new: String) {
        let root = NSTemporaryDirectory() + "support-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: root, withIntermediateDirectories: true)
        return (root + "/old", root + "/new")
    }

    private func makeTree(at path: String, linkingTo target: String? = nil) throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: path + "/buddies", withIntermediateDirectories: true)
        if let target {
            try manager.createSymbolicLink(
                atPath: path + "/buddies/emoji.buddy", withDestinationPath: target)
        }
    }

    @Test("nothing to move is not an error")
    func nothingToMove() throws {
        let (old, new) = try sandbox()
        #expect(SupportDirectory.migrate(from: old, to: new) == .notNeeded)
    }

    @Test("the old directory becomes the new one")
    func moves() throws {
        let (old, new) = try sandbox()
        try makeTree(at: old)
        #expect(SupportDirectory.migrate(from: old, to: new) == .moved(from: old))
        #expect(FileManager.default.fileExists(atPath: new + "/buddies"))
        #expect(FileManager.default.fileExists(atPath: old) == false)
    }

    // The buddies in there are usually links into a working copy. A migration
    // that resolved them would copy a snapshot and break hot reload: the file
    // being edited would no longer be the file being read.
    @Test("a symbolic link survives as a link")
    func keepsSymlinks() throws {
        let (old, new) = try sandbox()
        let target = NSTemporaryDirectory() + "target-\(UUID().uuidString).buddy"
        try "idle (x #FFFFFF)\n(o_o)".write(toFile: target, atomically: true, encoding: .utf8)
        try makeTree(at: old, linkingTo: target)

        #expect(SupportDirectory.migrate(from: old, to: new) == .moved(from: old))
        let moved = new + "/buddies/emoji.buddy"
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: moved)
        #expect(destination == target)
    }

    // Merging two trees is right nine times out of ten and destroys the tenth.
    // There is no reason to guess when a person can look.
    @Test("two directories are reported, never merged")
    func refusesToMerge() throws {
        let (old, new) = try sandbox()
        try makeTree(at: old)
        try makeTree(at: new)
        #expect(SupportDirectory.migrate(from: old, to: new) == .bothPresent(legacy: old))
        #expect(FileManager.default.fileExists(atPath: old))
    }

    @Test("migrating twice does nothing the second time")
    func isIdempotent() throws {
        let (old, new) = try sandbox()
        try makeTree(at: old)
        #expect(SupportDirectory.migrate(from: old, to: new) == .moved(from: old))
        #expect(SupportDirectory.migrate(from: old, to: new) == .notNeeded)
    }

    @Test("the buddies folder sits inside the support directory")
    func searchPathFollows() {
        #expect(BuddyLoader.searchPath == SupportDirectory.path + "/buddies")
        // Named from the product, not from a second literal that can drift.
        #expect(SupportDirectory.path.hasSuffix("/" + AppName.display))
    }

    // macOS volumes are usually case-insensitive, so the same directory answers
    // to two spellings and moving one onto the other fails. Detecting it by the
    // file system's own identifier is what keeps that from being reported as a
    // conflict the user has to resolve.
    @Test("two spellings of one directory are not a conflict")
    func caseInsensitiveIsSamePlace() throws {
        let (old, _) = try sandbox()
        try makeTree(at: old)
        let capitalised = (old as NSString).deletingLastPathComponent + "/OLD"
        guard FileManager.default.fileExists(atPath: capitalised) else {
            return   // case-sensitive volume: nothing to prove here
        }
        #expect(SupportDirectory.isSamePlace(old, capitalised))
        #expect(SupportDirectory.migrate(from: old, to: capitalised) == .notNeeded)
    }
}
