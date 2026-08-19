import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import NotchBuddyKit

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

    // The notch height is a hard ceiling: a buddy that overflows it is clipped,
    // not expressive. Every motion has to stay inside a few percent.
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

    @Test("only motions that show it ask for the expensive tier")
    func tiers() {
        #expect(MotionKind.none.preferredTier == .still)
        #expect(MotionKind.breathe.preferredTier == .ambient)
        #expect(MotionKind.bounce.preferredTier == .lively)
    }
}

@Suite("Buddy file format")
struct BuddyFileTests {

    private func parse(_ text: String) -> BuddyFile.ParseResult {
        BuddyFile.parse(text, id: "test", name: "Test")
    }

    // The format is what someone writes when asked to describe a buddy on a
    // napkin — because that is literally where it came from.
    @Test("a whole buddy parses")
    func fullBuddy() throws {
        let result = parse("""
        # commentaire

        sleeping (blue #00BBFF)
        ( -.- )
        ( -.- ) z

        idle (yellow #FFBB00)
        ( ^.^ )
        ( -.- )
        """)
        let m = try #require(result.manifest)
        #expect(result.problems.isEmpty)
        #expect(m.expressions.count == 2)
        #expect(m.expressions["sleeping"]?.frames.count == 2)
        #expect(m.expressions["idle"]?.frames == ["( ^.^ )", "( -.- )"])
    }

    @Test("the colour is read and the colour word ignored")
    func colourParsing() throws {
        let m = try #require(parse("idle (jaune vif #FFBB00)\n( ^.^ )").manifest)
        #expect(m.expressions["idle"]?.colour == "#FFBB00")
    }

    // Several of these faces are built out of their spacing.
    @Test("leading and trailing spaces in a frame survive")
    func spacingPreserved() throws {
        let m = try #require(parse("idle (x #FFFFFF)\n  ( ^.^ )  ").manifest)
        #expect(m.expressions["idle"]?.frames.first == "  ( ^.^ )  ")
    }

    @Test("comments and blank lines are not frames")
    func commentsIgnored() throws {
        let m = try #require(parse("""
        # un commentaire
        idle (x #FFFFFF)
        ( ^.^ )
        """).manifest)
        #expect(m.expressions["idle"]?.frames == ["( ^.^ )"])
    }

    // A buddy file is edited by hand, so half a buddy beats none — but a
    // problem must be reported rather than swallowed.
    @Test("a frame outside any section is reported, not silently dropped")
    func orphanFrameReported() {
        let result = parse("( ^.^ )\nidle (x #FFFFFF)\n( -.- )")
        #expect(result.manifest != nil)
        #expect(result.problems.count == 1)
        #expect(result.problems[0].contains("hors section"))
    }

    @Test("a section with no frames is reported")
    func emptySectionReported() {
        let result = parse("sleeping (x #FFFFFF)\n\nidle (x #FFFFFF)\n( ^.^ )")
        #expect(result.problems.contains { $0.contains("sleeping") })
    }

    @Test("a file without idle yields no buddy")
    func idleRequired() {
        let result = parse("working (x #FFFFFF)\n( o.o )")
        #expect(result.manifest == nil)
        #expect(result.problems.contains { $0.contains("idle") })
    }

    @Test("nonsense parses to nothing rather than crashing", arguments: [
        "", "   ", "####", "idle", "idle (no colour)", "(#FFFFFF)",
    ])
    func nonsenseIsSafe(_ text: String) {
        #expect(parse(text).manifest == nil)
    }
}

@Suite("Frame animation")
struct FrameTests {

    private func expression(_ frames: [String]) -> BuddyManifest.Expression {
        BuddyManifest.Expression(frames: frames, motion: .none, colour: nil)
    }

    @Test("frames advance one per second and wrap")
    func advancesAndWraps() {
        let e = expression(["a", "b", "c"])
        #expect(e.frame(at: 0.0) == "a")
        #expect(e.frame(at: 0.9) == "a")
        #expect(e.frame(at: 1.0) == "b")
        #expect(e.frame(at: 2.0) == "c")
        #expect(e.frame(at: 3.0) == "a")     // wrapped
        #expect(e.frame(at: 100.0) == "b")
    }

    @Test("a single frame never changes")
    func singleFrameIsStatic() {
        let e = expression(["only"])
        #expect(e.frame(at: 0) == "only")
        #expect(e.frame(at: 99) == "only")
    }

    // Sizing the slot from the *current* frame would resize the pill every
    // second as the animation cycles. The widest frame wins and nothing moves.
    @Test("the widest frame is what the layout measures")
    func widestWins() {
        let e = expression(["ab", "abcdef", "abc"])
        #expect(e.widestFrame == "abcdef")
    }

    @Test("every expression offers a candidate for the layout to measure")
    func candidatesAcrossExpressions() throws {
        let m = try #require(BuddyFile.parse("""
        idle (x #FFFFFF)
        ab

        sleeping (x #FFFFFF)
        abcdefghij
        """, id: "t", name: "T").manifest)
        let texts = Set(m.candidateFrames.map(\.text))
        #expect(texts == ["ab", "abcdefghij"])
    }

    // With per-expression sizes the longest frame is no longer necessarily the
    // widest: a short face at 20 pt beats a long one at 11. The layout has to
    // measure each candidate at its own size, so the manifest must hand over
    // both — not a single pre-chosen "widest" string.
    @Test("a candidate carries the size it will be drawn at")
    func candidateCarriesItsSize() throws {
        let m = try #require(BuddyFile.parse("""
        idle (x #FFFFFF) 11
        aaaaaaaaaa

        working (x #FFFFFF) 22
        oo
        """, id: "t", name: "T").manifest)
        let sizes = Dictionary(uniqueKeysWithValues: m.candidateFrames.map { ($0.text, $0.size) })
        #expect(sizes["aaaaaaaaaa"] == 11)
        #expect(sizes["oo"] == 22)
    }

    @Test("speed is read as images per second and inverted for the renderer")
    func speedDirective() throws {
        let m = try #require(BuddyFile.parse("""
        size: 14
        speed: 4
        idle (x #FFFFFF)
        ab
        cd
        """, id: "t", name: "T").manifest)
        #expect(m.framesPerSecond == 4)
        #expect(m.secondsPerFrame(for: m.expressions["idle"]) == 0.25)
        // Faster means the frames actually come sooner, not just a stored number.
        #expect(m.expressions["idle"]?.frame(at: 0.3, secondsPerFrame: 0.25) == "cd")
    }

    @Test("a file that says nothing keeps one frame per second")
    func speedDefaults() throws {
        let m = try #require(BuddyFile.parse("""
        idle (x #FFFFFF)
        ab
        """, id: "t", name: "T").manifest)
        #expect(m.framesPerSecond == BuddyManifest.defaultFrameRate)
        #expect(m.secondsPerFrame(for: m.expressions["idle"]) == 1)
    }

    @Test("an expression overrides the file's speed, size first")
    func perExpressionSpeed() throws {
        let m = try #require(BuddyFile.parse("""
        size: 14
        speed: 2
        idle (x #FFFFFF)
        ab

        working (x #FFFFFF) 20 8
        cd

        sleeping (x #FFFFFF) 0.5
        ef
        """, id: "t", name: "T").manifest)
        #expect(m.rate(for: m.expressions["idle"]) == 2)
        #expect(m.size(for: m.expressions["working"]) == 20)
        #expect(m.rate(for: m.expressions["working"]) == 8)
        // `0.5` cannot be a size — sizes are whole — so it lands on the speed.
        #expect(m.rate(for: m.expressions["sleeping"]) == 0.5)
        #expect(m.size(for: m.expressions["sleeping"]) == 14)
    }

    // Clamping would hide the mistake: a file asking for 200 images per second
    // would draw at 30 and its author would never learn why.
    @Test("an out-of-range speed is refused, not clamped")
    func speedOutOfRangeIsReported() throws {
        let result = BuddyFile.parse("""
        speed: 200
        idle (x #FFFFFF)
        ab
        """, id: "t", name: "T")
        let m = try #require(result.manifest)
        #expect(m.framesPerSecond == BuddyManifest.defaultFrameRate)
        #expect(result.problems.count == 1)

        let perExpression = BuddyFile.parse("""
        idle (x #FFFFFF) 14 0.001
        ab
        """, id: "t", name: "T")
        #expect(perExpression.manifest?.expressions["idle"]?.framesPerSecond == nil)
        #expect(perExpression.problems.count == 1)
    }

    @Test("validation rejects a rate outside the bounds")
    func validationRejectsBadRate() throws {
        let m = BuddyManifest(
            schema: BuddyManifest.supportedSchema, kind: .ascii, id: "t", name: "T",
            colour: "#FFFFFF", fontSize: 13, framesPerSecond: 999, font: nil,
            expressions: ["idle": BuddyManifest.Expression(
                frames: ["ab"], motion: .none, colour: nil)])
        #expect(throws: BuddyManifest.ValidationError.badFrameRate(999)) { try m.validate() }
    }

    @Test("an expression without a size falls back to the file's")
    func sizeFallsBack() throws {
        let m = try #require(BuddyFile.parse("""
        size: 14
        idle (x #FFFFFF)
        ab

        working (x #FFFFFF) 20
        cd
        """, id: "t", name: "T").manifest)
        #expect(m.size(for: m.expressions["idle"]) == 14)
        #expect(m.size(for: m.expressions["working"]) == 20)
    }
}

@Suite("Built-in buddy")
struct BuiltInBuddyTests {

    @Test("it parses and validates")
    func builtInIsValid() throws {
        let m = BuiltInBuddy.manifest
        #expect(m.id == "orb")
        try m.validate()
        #expect(m.expressions.count == BuddyExpression.allCases.count)
    }

    @Test("every expression animates")
    func allAnimate() {
        for e in BuiltInBuddy.manifest.expressions.values {
            #expect(e.frames.count > 1)
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
