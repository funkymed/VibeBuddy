import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import VibeBuddyKit

@Suite("Motion vocabulary")
struct MotionTests {
    @Test("none is perfectly still, at any phase")
    func noneIsStill() {
        for phase in [0.0, 1.0, 7.3, 1000.0] {
            let t = MotionKind.none.transform(at: phase)
            #expect(t.scale == 1)
            #expect(t.offset == .zero)
            #expect(t.gaze == .zero)
        }
    }

    // The notch height is a hard ceiling: a buddy that overflows it is clipped, not
    // expressive.
    @Test("every motion stays within its bounds", arguments: MotionKind.allCases)
    func boundedAmplitude(_ motion: MotionKind) {
        for step in 0..<400 {
            let t = motion.transform(at: Double(step) * 0.05)
            #expect(abs(t.scale - 1) <= 0.08, "\(motion) scaled by \(t.scale)")
            #expect(abs(t.offset.height) <= 6, "\(motion) moved \(t.offset.height) pt")
            #expect(abs(t.offset.width) <= 6)
            #expect(abs(t.gaze.width) <= 8)
        }
    }

    @Test("transient motions settle towards nothing")
    func transientsDecay() {
        for motion in MotionKind.allCases where motion.isTransient {
            let early = motion.transform(at: 0.15)
            let late = motion.transform(at: 3.0)
            let earlyMagnitude = abs(early.offset.width) + abs(early.offset.height)
            let lateMagnitude = abs(late.offset.width) + abs(late.offset.height)
            #expect(lateMagnitude < earlyMagnitude, "\(motion) never settles")
            #expect(lateMagnitude < 0.1)
        }
    }

}

@Suite("Buddy file format")
struct BuddyFileTests {
    static let source = """
    # a comment, not a colour
    face: 80x30 oval

    idle (amber #FFBB00)
    eye   shape:oval w:9 h:13 r:4.5 gap:20 y:-3
    mouth shape:arc w:24 h:9 t:0.6 bend:1 y:8
    time  beat:1.6 blink:0.3 gaze:wander

    failed (red #FF5555)
    eye   shape:wing w:18 h:11 t:0.55 bend:1 gap:8 y:-4
    time  beat:1.5 glitch:0.85 gaze:none
    """

    @Test("a whole buddy parses")
    func parsesWholeFile() throws {
        let result = BuddyFile.parse(Self.source, id: "t", name: "T")
        let m = try #require(result.manifest)
        #expect(result.problems.isEmpty, "\(result.problems)")
        #expect(m.expressions.count == 2)
        #expect(m.face.silhouette == .oval)
        #expect(m.face.width == 80)
        #expect(throws: Never.self) { try m.validate() }
    }

    @Test("the colour is read and the colour word ignored")
    func colourWordIsDecoration() throws {
        let m = try #require(BuddyFile.parse(Self.source, id: "t", name: "T").manifest)
        #expect(m.expressions["idle"]?.colour == "#FFBB00")
        #expect(m.expressions["failed"]?.colour == "#FF5555")
        // The manifest colour is idle's: it is the face you see most.
        #expect(m.colour == "#FFBB00")
    }

    @Test("motion is derived from the expression, and only reactions move")
    func motionIsDerived() throws {
        let m = try #require(BuddyFile.parse(Self.source, id: "t", name: "T").manifest)
        #expect(m.expressions["idle"]?.motion == MotionKind.none)
        #expect(m.expressions["failed"]?.motion == .shake)
    }

    @Test("a line outside any section is reported, not silently dropped")
    func strayLineIsReported() {
        let result = BuddyFile.parse("""
        eye shape:oval

        idle (x #FFFFFF)
        eye shape:oval
        """, id: "t", name: "T")
        #expect(result.problems.contains { $0.contains("hors section") })
    }

    @Test("a directive from the glyph format is reported rather than swallowed")
    func retiredDirectivesAreReported() {
        for key in ["kind", "font", "size", "speed"] {
            let result = BuddyFile.parse("""
            \(key): 13

            idle (x #FFFFFF)
            eye shape:oval
            """, id: "t", name: "T")
            #expect(result.problems.contains { $0.contains(key) }, "\(key)")
        }
    }

    @Test("a file without idle yields no buddy")
    func idleIsMandatory() {
        let result = BuddyFile.parse("""
        working (x #FFFFFF)
        eye shape:oval
        """, id: "t", name: "T")
        #expect(result.manifest == nil)
        #expect(result.problems.contains { $0.contains("idle") })
    }

    @Test("an unreadable face falls back rather than failing the file")
    func badFaceFallsBack() throws {
        let result = BuddyFile.parse("""
        face: not-a-size

        idle (x #FFFFFF)
        eye shape:oval
        """, id: "t", name: "T")
        let m = try #require(result.manifest)
        #expect(result.problems.contains { $0.contains("face") })
        #expect(throws: Never.self) { try m.validate() }
    }

    @Test("nonsense parses to nothing rather than crashing", arguments: [
        "", "\n\n\n", "####", "(((", "idle", "idle (#ZZZZZZ)", "face: 80x30 oval",
    ])
    func nonsenseIsSafe(_ text: String) {
        #expect(BuddyFile.parse(text, id: "t", name: "T").manifest == nil)
    }
}

@Suite("Built-in buddy")
struct BuiltInBuddyTests {
    @Test("it parses and validates")
    func builtInIsValid() throws {
        let m = BuiltInBuddy.manifest
        #expect(m.id == BuiltInBuddy.id)
        try m.validate()
        #expect(m.expressions.count == BuddyExpression.allCases.count)
    }

    @Test("it is byte-for-byte the file a person edits")
    func builtInMatchesTheAsset() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let onDisk = try String(
            contentsOf: root.appendingPathComponent("assets/buddies/eve.buddy"), encoding: .utf8)
        #expect(onDisk.trimmingCharacters(in: .whitespacesAndNewlines)
                == BuiltInBuddy.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("every expression has a face, and the screen can hold it")
    func allHaveFaces() throws {
        let m = BuiltInBuddy.manifest
        for name in BuddyExpression.allCases {
            let e = try #require(m.expressions[name.rawValue], "\(name)")
            let eye = e.eye.pose.eye
            #expect(eye.width > 0 && eye.height > 0, "\(name)")
            // Both eyes plus the gap, at the widest the animation ever makes them, have
            // to fit across the screen.
            #expect(e.eye.pose.gap + eye.width * 2 * EyeSpec.nearer <= m.face.width, "\(name)")
            #expect(eye.height * EyeSpec.nearer <= m.face.height, "\(name)")
        }
    }

    @Test("a missing buddy falls back to the built-in one")
    func missingFallsBack() {
        var loader = BuddyLoader()
        let loaded = loader.load(id: "does-not-exist")
        #expect(loaded.isFallback)
        #expect(loaded.manifest.id == BuiltInBuddy.id)
        #expect(loader.problems.count == 1)
    }

    @Test("hex colours parse in both lengths, and nonsense does not")
    func colours() {
        #expect(Color(hex: "#FE9C19") != nil)
        #expect(Color(hex: "#00000000") != nil)
        #expect(Color(hex: "#GGGGGG") == nil)
        #expect(Color(hex: "#FFF") == nil)
    }
}

@Suite("Expression mapping")
struct BuddyExpressionTests {
    @Test("hidden always sleeps, whatever is happening")
    func hiddenSleeps() {
        #expect(BuddyExpression.from(activity: .working, hasLiveSession: true, isVisible: false) == .sleeping)
    }

    @Test("no live session sleeps")
    func noSessionSleeps() {
        #expect(BuddyExpression.from(activity: nil, hasLiveSession: false, isVisible: true) == .sleeping)
    }

    @Test("session states map to faces", arguments: [
        (SessionActivity.working,  BuddyExpression.working),
        (.finished, .finished),
        (.failed,   .failed),
        (.idle,     .idle),
    ])
    func mapping(_ activity: SessionActivity, _ expected: BuddyExpression) {
        #expect(BuddyExpression.from(activity: activity, hasLiveSession: true, isVisible: true) == expected)
    }
}
