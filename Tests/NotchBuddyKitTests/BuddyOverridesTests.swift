import Foundation
import Testing
@testable import NotchBuddyKit

/// The editing layer, and the round trip that keeps it shareable.
@Suite("Buddy overrides")
struct BuddyOverridesTests {

    private func manifest() -> BuddyManifest {
        BuddyFile.parse("""
        size: 15
        speed: 1

        idle (x #FFBB00)
        (^.^)
        (-.-)

        working (x #55FF55) 12 3
        (o.o)
        (O.O)
        """, id: "test", name: "Test").manifest!
    }

    @Test("no edits means the manifest is returned untouched")
    func identity() {
        let base = manifest()
        #expect(BuddyOverrides().apply(to: base) == base)
    }

    @Test("an edit replaces only what it names")
    func partialEdit() {
        var overrides = BuddyOverrides()
        overrides.set(.init(frames: ["(¬_¬)"]), for: "idle", of: "test")
        let resolved = overrides.apply(to: manifest())
        #expect(resolved.expressions["idle"]?.frames == ["(¬_¬)"])
        // Everything unnamed still comes from the file.
        #expect(resolved.expressions["working"]?.frames == ["(o.o)", "(O.O)"])
        #expect(resolved.rate(for: resolved.expressions["working"]) == 3)
    }

    @Test("each field can be overridden on its own")
    func everyField() {
        var overrides = BuddyOverrides()
        overrides.set(
            .init(colour: "#FF0000", fontSize: 22, framesPerSecond: 4, motion: .bounce),
            for: "idle", of: "test")
        let resolved = overrides.apply(to: manifest())
        let idle = resolved.expressions["idle"]
        #expect(idle?.colour == "#FF0000")
        #expect(resolved.size(for: idle) == 22)
        #expect(resolved.rate(for: idle) == 4)
        #expect(idle?.motion == .bounce)
        // Untouched: the frames still come from the file.
        #expect(idle?.frames == ["(^.^)", "(-.-)"])
    }

    // A reset must leave no trace, or every listing would show an expression as
    // edited forever.
    @Test("resetting removes the record entirely")
    func resetLeavesNothing() {
        var overrides = BuddyOverrides()
        overrides.set(.init(frames: ["a"]), for: "idle", of: "test")
        #expect(overrides.hasEdits(for: "test"))
        overrides.reset("idle", of: "test")
        #expect(overrides.hasEdits(for: "test") == false)
        #expect(overrides.apply(to: manifest()) == manifest())
    }

    @Test("an edit that stores nothing is not stored")
    func emptyEditIsDropped() {
        var overrides = BuddyOverrides()
        overrides.set(BuddyOverrides.Expression(), for: "idle", of: "test")
        #expect(overrides.hasEdits(for: "test") == false)
    }

    // An expression whose frames are all blank renders nothing at all. Falling
    // back to the file is the honest reading of "no frames".
    @Test("blanking every frame falls back to the file")
    func blankFramesIgnored() {
        var overrides = BuddyOverrides()
        overrides.set(.init(frames: ["", "  "]), for: "idle", of: "test")
        let resolved = overrides.apply(to: manifest())
        #expect(resolved.expressions["idle"]?.frames == ["(^.^)", "(-.-)"])
    }

    @Test("a buddy created in the app needs no file")
    func createdBuddy() throws {
        var overrides = BuddyOverrides()
        overrides.created["mine"] = .init(
            name: "Mine", expressions: ["idle": .init(frames: ["(o_o)"])])
        let manifest = try #require(overrides.manifest(forCreated: "mine"))
        #expect(manifest.id == "mine")
        #expect(manifest.expressions["idle"]?.frames == ["(o_o)"])
        try manifest.validate()
    }

    @Test("a created buddy without idle is refused rather than half-built")
    func createdNeedsIdle() {
        var overrides = BuddyOverrides()
        overrides.created["mine"] = .init(
            name: "Mine", expressions: ["working": .init(frames: ["(o_o)"])])
        #expect(overrides.manifest(forCreated: "mine") == nil)
    }

    @Test("the layer survives encoding")
    func codableRoundTrip() {
        var overrides = BuddyOverrides()
        overrides.set(.init(frames: ["a", "b"], motion: .shake), for: "failed", of: "test")
        overrides.created["mine"] = .init(name: "Mine")
        #expect(BuddyOverrides.decode(overrides.encoded()) == overrides)
    }

    @Test("garbage decodes to an empty layer rather than trapping")
    func decodeGarbage() {
        #expect(BuddyOverrides.decode(Data("not json".utf8)) == BuddyOverrides())
        #expect(BuddyOverrides.decode(nil) == BuddyOverrides())
    }

    // The escape hatch. Without it an edit could never leave this machine.
    @Test("exporting then reparsing gives back the edited buddy")
    func exportRoundTrip() throws {
        var overrides = BuddyOverrides()
        overrides.set(
            .init(frames: ["(¬_¬)", "(o_o)"], colour: "#FF0000",
                  fontSize: 18, framesPerSecond: 2),
            for: "idle", of: "test")
        let edited = overrides.apply(to: manifest())

        let text = BuddyExportWriter.text(for: edited)
        let reparsed = try #require(BuddyFile.parse(text, id: "test", name: "Test").manifest)

        let idle = reparsed.expressions["idle"]
        #expect(idle?.frames == ["(¬_¬)", "(o_o)"])
        #expect(idle?.colour == "#FF0000")
        #expect(reparsed.size(for: idle) == 18)
        #expect(reparsed.rate(for: idle) == 2)
        // The untouched expression survives the trip too, overrides and all.
        #expect(reparsed.rate(for: reparsed.expressions["working"]) == 3)
    }

    // A speed override with no size would be read back as a size: the format is
    // positional.
    @Test("a speed override forces its size to be written")
    func exportWritesSizeBeforeSpeed() throws {
        var overrides = BuddyOverrides()
        overrides.set(.init(framesPerSecond: 5), for: "idle", of: "test")
        let text = BuddyExportWriter.text(for: overrides.apply(to: manifest()))
        let reparsed = try #require(BuddyFile.parse(text, id: "t", name: "T").manifest)
        #expect(reparsed.rate(for: reparsed.expressions["idle"]) == 5)
        #expect(reparsed.size(for: reparsed.expressions["idle"]) == 15)
    }

    @Test("exporting twice gives the same bytes")
    func exportIsStable() {
        let manifest = manifest()
        #expect(BuddyExportWriter.text(for: manifest) == BuddyExportWriter.text(for: manifest))
    }

    @Test("an export never silently replaces an existing file")
    func refusesToOverwrite() throws {
        let path = NSTemporaryDirectory() + "export-\(UUID().uuidString).buddy"
        #expect(BuddyExportWriter.write(manifest(), to: path) == .success(path))
        #expect(BuddyExportWriter.write(manifest(), to: path) == .failure(.exists))
        #expect(BuddyExportWriter.write(manifest(), to: path, overwrite: true) == .success(path))
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// The ungrouped path exists so the "group by folder" preference does not need
/// a second kind of row.
@Suite("Ungrouped sessions")
struct UngroupedSessionsTests {

    private func session(id: String, cwd: String, live: Bool) -> AgentSession {
        AgentSession(
            id: id, cwd: cwd, projectName: (cwd as NSString).lastPathComponent,
            model: "", startedAt: Date(), lastActivity: Date(),
            status: "", action: .none, permissionMode: "",
            contextTokens: 0, contextWindow: 200_000, pid: nil, isLive: live)
    }

    @Test("two sessions in one folder stay two rows")
    func keepsBoth() {
        let rows = SessionGroup.ungrouped([
            session(id: "a", cwd: "/p", live: false),
            session(id: "b", cwd: "/p", live: true),
        ])
        #expect(rows.count == 2)
        // Distinct ids, or `ForEach` would drop one of them.
        #expect(Set(rows.map(\.id)).count == 2)
        // Live first, same rule as grouped.
        #expect(rows.first?.primary.id == "b")
        #expect(rows.allSatisfy { $0.hasHistory == false })
    }
}
