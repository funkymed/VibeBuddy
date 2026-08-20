import Foundation
import Testing
@testable import VibeBuddyKit

/// The editing layer, and the round trip that keeps it shareable.
@Suite("Buddy overrides")
struct BuddyOverridesTests {

    private func manifest() -> BuddyManifest {
        BuddyFile.parse("""
        face: 80x30 oval

        idle (x #FFBB00)
        eye   shape:oval w:9 h:13 r:4.5 gap:20 y:-3
        mouth shape:arc w:24 h:9 t:0.6 bend:1 y:8
        time  beat:1.6 blink:0.3 gaze:wander

        working (x #55FF55)
        eye  shape:ring w:16 h:16 t:0.26 gap:14 y:-3
        time beat:1.2 blink:0.2 gaze:scan
        """, id: "test", name: "Test").manifest!
    }

    private func pose(_ shape: EyeShape) -> EyeSpec {
        EyeSpec(pose: EyePose(eye: FaceFeature(shape: shape, width: 11, height: 11)))
    }

    @Test("no edits means the manifest is returned untouched")
    func identity() {
        let base = manifest()
        #expect(BuddyOverrides().apply(to: base) == base)
    }

    @Test("an edit replaces only what it names")
    func partialEdit() {
        var overrides = BuddyOverrides()
        overrides.set(.init(eye: pose(.x)), for: "idle", of: "test")
        let resolved = overrides.apply(to: manifest())
        #expect(resolved.expressions["idle"]?.eye.pose.eye.shape == .x)
        // Everything unnamed still comes from the file.
        #expect(resolved.expressions["working"]?.eye.pose.eye.shape == .ring)
        #expect(resolved.expressions["working"]?.eye.gaze == .scan)
    }

    @Test("each field can be overridden on its own")
    func everyField() {
        var overrides = BuddyOverrides()
        overrides.set(.init(colour: "#FF0000", motion: .bounce), for: "idle", of: "test")
        let resolved = overrides.apply(to: manifest())
        let idle = resolved.expressions["idle"]
        #expect(idle?.colour == "#FF0000")
        #expect(idle?.motion == .bounce)
        // Untouched: the face still comes from the file.
        #expect(idle?.eye.pose.eye.shape == .oval)
        #expect(idle?.eye.pose.mouth != nil)
    }

    // A reset must leave no trace, or every listing would show an expression as
    // edited forever.
    @Test("resetting removes the record entirely")
    func resetLeavesNothing() {
        var overrides = BuddyOverrides()
        overrides.set(.init(colour: "#FF0000"), for: "idle", of: "test")
        #expect(overrides.hasEdits(for: "test"))
        overrides.reset("idle", of: "test")
        #expect(!overrides.hasEdits(for: "test"))
        #expect(overrides.edits["test"] == nil)
    }

    @Test("an edit that stores nothing is not stored")
    func emptyEditIsNotAnEdit() {
        var overrides = BuddyOverrides()
        overrides.set(.init(), for: "idle", of: "test")
        #expect(!overrides.hasEdits(for: "test"))
    }

    @Test("an edit naming no face falls back to the file")
    func faceFallsBack() {
        var overrides = BuddyOverrides()
        overrides.set(.init(colour: "#00FF00"), for: "idle", of: "test")
        let resolved = overrides.apply(to: manifest())
        #expect(resolved.expressions["idle"]?.eye == manifest().expressions["idle"]?.eye)
        #expect(resolved.expressions["idle"]?.colour == "#00FF00")
    }

    @Test("a buddy created in the app needs no file")
    func createdBuddy() throws {
        var overrides = BuddyOverrides()
        var created = BuddyOverrides.Created(name: "Mine", colour: "#00FF00")
        created.expressions["idle"] = .init(colour: "#00FF00", eye: pose(.oval))
        overrides.created["mine"] = created
        let m = try #require(overrides.manifest(forCreated: "mine"))
        #expect(m.name == "Mine")
        #expect(m.expressions["idle"]?.eye.pose.eye.shape == .oval)
        #expect(throws: Never.self) { try m.validate() }
    }

    @Test("a created buddy without idle is refused rather than half-built")
    func createdNeedsIdle() {
        var overrides = BuddyOverrides()
        var created = BuddyOverrides.Created(name: "Mine")
        created.expressions["working"] = .init(eye: pose(.oval))
        overrides.created["mine"] = created
        #expect(overrides.manifest(forCreated: "mine") == nil)
    }

    @Test("the layer survives encoding")
    func codableRoundTrip() {
        var overrides = BuddyOverrides()
        overrides.set(.init(eye: pose(.x), motion: .shake), for: "failed", of: "test")
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
        overrides.set(.init(colour: "#FF0000", eye: pose(.caret)), for: "idle", of: "test")
        let resolved = overrides.apply(to: manifest())
        let text = BuddyExportWriter.text(for: resolved, name: "Exported")
        let result = BuddyFile.parse(text, id: "test", name: "Test")
        let reparsed = try #require(result.manifest)
        #expect(result.problems.isEmpty, "\(result.problems)")
        #expect(reparsed.face == resolved.face)
        for name in BuddyExpression.allCases {
            #expect(reparsed.expressions[name.rawValue]?.eye
                    == resolved.expressions[name.rawValue]?.eye, "\(name)")
            #expect(reparsed.expressions[name.rawValue]?.colour
                    == resolved.expressions[name.rawValue]?.colour, "\(name)")
        }
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
            status: nil, action: .none, permissionMode: "",
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

/// The model label on a row.
@Suite("Model names")
struct ModelNameTests {

    // The version is the half that distinguishes two sessions. Cutting at the
    // first dash — the first implementation — kept only the half that cannot.
    @Test("the family keeps its version")
    func keepsVersion() {
        #expect(ModelName.short("claude-opus-5") == "opus 5")
        #expect(ModelName.short("claude-sonnet-5") == "sonnet 5")
        #expect(ModelName.short("claude-opus-4-8") == "opus 4.8")
        #expect(ModelName.short("claude-haiku-4-5") == "haiku 4.5")
    }

    @Test("a build date is not a model")
    func dropsDateStamp() {
        #expect(ModelName.short("claude-haiku-4-5-20251001") == "haiku 4.5")
    }

    // `[1m]` selects the context window, which the panel already shows as a
    // gauge. It is configuration, not identity.
    @Test("the window marker is not part of the name")
    func dropsWindowMarker() {
        #expect(ModelName.short("claude-opus-5[1m]") == "opus 5")
        #expect(ModelName.short("opus[1m]") == "opus")
    }

    @Test("an unknown shape is shown as it came")
    func unknownIsUntouched() {
        #expect(ModelName.short("gpt-5") == "gpt 5")
        #expect(ModelName.short("mistral") == "mistral")
        #expect(ModelName.short("") == "")
    }
}
