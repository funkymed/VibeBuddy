import Testing
import Foundation
import CoreGraphics
@testable import VibeBuddyKit

/// The shipped eyes buddy, read from disk rather than duplicated here: a copy
/// would keep passing after the real file broke.
@MainActor
enum EveFixture {
    static let manifest: BuddyManifest = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = (try? String(
            contentsOf: root.appendingPathComponent("assets/buddies/eve.buddy"),
            encoding: .utf8)) ?? ""
        return BuddyFile.parse(text, id: "eve", name: "Eve").manifest ?? BuddyManifest.empty
    }()
}

@Suite("Eyes: the .buddy dialect")
struct EyesFileTests {

    static let source = """
    face: 58x28 r10

    idle (cyan #5AB8FF)
    eye   shape:oval w:7 h:12 r:3.5 gap:13 y:-4
    mouth shape:arc w:18 h:8 t:0.62 bend:1 y:7
    time  beat:0.55 blink:0.3 gaze:wander

    failed (red #FF5555)
    eye   shape:wing w:13 h:10 t:0.6 bend:1 gap:6 y:-4
    time  beat:0.5 blink:0.22 gaze:none
    """

    @Test("kind and face survive the parse")
    func parsesPlate() throws {
        let result = BuddyFile.parse(Self.source, id: "eve", name: "Eve")
        let manifest = try #require(result.manifest)
        #expect(manifest.face.width == 58)
        #expect(manifest.face.height == 28)
        #expect(manifest.face.radius == 10)
        #expect(manifest.face.silhouette == .rounded)
        #expect(result.problems.isEmpty)
        #expect(throws: Never.self) { try manifest.validate() }
    }

    @Test("every pose key lands where it is meant to")
    func parsesPose() throws {
        let manifest = try #require(BuddyFile.parse(Self.source, id: "eve", name: "Eve").manifest)
        let idle = try #require(manifest.expressions["idle"]).eye
        #expect(idle.pose.eye.shape == .oval)
        #expect(idle.pose.eye.width == 7)
        #expect(idle.pose.eye.height == 12)
        #expect(idle.pose.eye.radius == 3.5)
        #expect(idle.pose.eye.offsetY == -4)
        #expect(idle.pose.gap == 13)
        #expect(idle.beat == 0.55)
        #expect(idle.blink == 0.3)
        #expect(idle.gaze == .wander)

        let mouth = try #require(idle.pose.mouth)
        #expect(mouth.shape == .arc)
        #expect(mouth.width == 18)
        #expect(mouth.bend == 1)
        #expect(mouth.offsetY == 7)

        let failed = try #require(manifest.expressions["failed"]).eye
        #expect(failed.pose.eye.shape == .wing)
        #expect(failed.pose.eye.thickness == 0.6)
        #expect(failed.gaze == .none)
        // No `mouth` line means no mouth, not a mouth of size zero.
        #expect(failed.pose.mouth == nil)
    }

    @Test("the ear is sized from the screen, not from anything measured")
    func slotComesFromTheScreen() throws {
        let manifest = try #require(BuddyFile.parse(Self.source, id: "eve", name: "Eve").manifest)
        #expect(manifest.face.width == 58)
    }

    @Test("an unknown key, or an unknown shape, is reported rather than guessed")
    func reportsUnknown() {
        let keys = BuddyFile.parse("""
        idle (cyan #5AB8FF)
        eye w:7 wobble:3
        """, id: "x", name: "X")
        #expect(keys.problems.contains { $0.contains("wobble") })

        let shape = BuddyFile.parse("""
        idle (cyan #5AB8FF)
        eye shape:triangle
        """, id: "x", name: "X")
        #expect(shape.problems.contains { $0.contains("triangle") })

        let head = BuddyFile.parse("""
        idle (cyan #5AB8FF)
        nose shape:oval
        """, id: "x", name: "X")
        #expect(head.problems.contains { $0.contains("nose") })
    }

    @Test("kind: eyes without face: still has a face")
    func defaultsThePlate() throws {
        let manifest = try #require(BuddyFile.parse("""
        idle (cyan #5AB8FF)
        eye w:7 h:10
        """, id: "x", name: "X").manifest)
        #expect(manifest.face.width > 0)
        #expect(throws: Never.self) { try manifest.validate() }
    }

    @Test("an eyes section describing nothing is refused, not drawn empty")
    func refusesEmptySection() {
        #expect(BuddyFile.parse("""
        idle (cyan #5AB8FF)
        """, id: "x", name: "X").manifest == nil)
    }

    @MainActor
    @Test("the shipped eve.buddy parses, validates, and covers every state")
    func shippedBuddy() throws {
        let manifest = EveFixture.manifest
        #expect(manifest.id == "eve")
        #expect(throws: Never.self) { try manifest.validate() }
        for name in BuddyExpression.allCases {
            #expect(manifest.expressions[name.rawValue]?.eye.pose.eye.width ?? 0 > 0, "\(name)")
        }
        #expect(manifest.expressions["finished"]?.eye.pose.eye.shape == .arc)
        #expect(manifest.expressions["failed"]?.eye.pose.eye.shape == .wing)
        #expect(manifest.expressions["working"]?.eye.pose.eye.shape == .ring)
        for name in BuddyExpression.allCases {
            #expect(manifest.expressions[name.rawValue]?.eye.pose.mouth != nil, "\(name)")
        }
    }

    @MainActor
    @Test("an exported eyes buddy parses back to the same thing")
    func exportRoundTrips() throws {
        let original = EveFixture.manifest
        let text = BuddyExportWriter.text(for: original)
        let result = BuddyFile.parse(text, id: "eve", name: "Eve")
        let reparsed = try #require(result.manifest)
        #expect(result.problems.isEmpty, "\(result.problems)")
        #expect(reparsed.face == original.face)
        for name in BuddyExpression.allCases {
            #expect(reparsed.expressions[name.rawValue]?.eye
                    == original.expressions[name.rawValue]?.eye, "\(name)")
        }
    }
}

@Suite("Eyes: the beat sequence")
struct EyeBeatTests {

    static let spec = EyeSpec(
        pose: EyePose(
            eye: FaceFeature(shape: .oval, width: 7, height: 12, radius: 3.5, offsetY: -4),
            gap: 13,
            mouth: FaceFeature(shape: .arc, width: 18, height: 8, thickness: 0.62,
                               bend: 1, offsetY: 7)),
        beat: 1.6, blink: 0.3, gaze: .wander)

    @Test("the same phase always gives the same face")
    func deterministic() {
        for step in 0..<400 {
            let phase = Double(step) * 0.037
            #expect(EyeAnimation.at(phase: phase, spec: Self.spec)
                    == EyeAnimation.at(phase: phase, spec: Self.spec))
        }
    }

    @Test("a beat holds still for its whole length, then snaps")
    func beatsAreSteps() {
        let beat = Self.spec.beat
        for index in 0..<40 {
            let start = Double(index) * beat
            let expected = EyeAnimation.at(phase: start + 0.001, spec: Self.spec).gaze
            // Sampled after the blink window, where openness is settled and
            // only the gaze is under test.
            for offset in stride(from: 0.5, to: 0.99, by: 0.05) {
                let sample = EyeAnimation.at(phase: start + beat * offset, spec: Self.spec)
                #expect(sample.gaze == expected, "beat \(index) moved mid-beat")
            }
        }
    }

    @Test("blink: 0 never shuts an eye")
    func neverBlinks() {
        var spec = Self.spec
        spec.blink = 0
        for step in 0..<2000 {
            let frame = EyeAnimation.at(phase: Double(step) * 0.02, spec: spec)
            #expect(frame.beat != .blink)
            #expect(frame.openness == 1)
        }
    }

    @Test("blinks do happen, and are shorter than the beat that holds them")
    func blinksHappen() {
        var shut = 0, seen = 0
        for step in 0..<4000 {
            let frame = EyeAnimation.at(phase: Double(step) * 0.01, spec: Self.spec)
            if frame.beat == .blink { seen += 1 }
            if frame.openness == 0 { shut += 1 }
        }
        #expect(seen > 0, "no blink in 40 s")
        #expect(shut > 0)
        #expect(Double(shut) < Double(seen) * 0.6, "the lid stayed shut for the whole beat")
    }

    @Test("a lid that shuts widens the eye — squash and stretch")
    func squashAndStretch() {
        var widest: CGFloat = 1
        for step in 0..<4000 {
            let frame = EyeAnimation.at(phase: Double(step) * 0.01, spec: Self.spec)
            #expect(frame.stretch >= 1)
            widest = max(widest, frame.stretch)
        }
        #expect(widest > 1.2, "eyes never stretched: \(widest)")
    }

    @Test("an expression only ever looks where its repertoire allows")
    func repertoireIsRespected() {
        for kind in GazeKind.allCases {
            var spec = Self.spec
            spec.gaze = kind
            spec.blink = 0
            let allowed = Set(kind.repertoire)
            var seen: Set<EyeBeat> = []
            for index in 0..<400 {
                let beat = EyeAnimation.beat(at: index, spec: spec)  // swiftlint:disable:this identifier_name
                #expect(allowed.contains(beat), "\(kind) looked \(beat)")
                seen.insert(beat)
            }
            if kind != .none { #expect(seen.count > 1, "\(kind) never moved") }
        }
    }

    @Test("the eyes never sit on one spot for long")
    func looksDoNotStick() {
        for kind in [GazeKind.wander, .scan, .dart] {
            var spec = Self.spec
            spec.gaze = kind
            var run = 0, longest = 0
            var lastLook: EyeBeat?
            var seen: Set<EyeBeat> = []
            for index in 0..<600 {
                let current = EyeAnimation.beat(at: index, spec: spec)
                // A blink between two identical looks breaks the run: the face
                // visibly changed, so nothing reads as stuck. "Ahead, blink,
                // ahead" is a normal thing for a face to do.
                guard current != .blink else { lastLook = nil; run = 0; continue }
                seen.insert(current)
                run = current == lastLook ? run + 1 : 1
                longest = max(longest, run)
                lastLook = current
            }
            // One, except where the walk restarts every 64 beats and may
            // land on the look it left off — see EyeAnimation.rawPick.
            #expect(longest <= 2, "\(kind) held one look \(longest) beats running")
            #expect(seen.count >= min(3, kind.repertoire.count), "\(kind) barely moved")
        }
    }

    @Test("a blink holds the look it interrupted rather than snapping to centre")
    func blinkHoldsTheLook() {
        for index in 1..<500 where EyeAnimation.beat(at: index, spec: Self.spec) == .blink {
            let previous = EyeAnimation.beat(at: index - 1, spec: Self.spec)
            guard previous != .blink else { continue }
            let during = EyeAnimation.at(
                phase: Double(index) * Self.spec.beat + 0.01, spec: Self.spec)
            let before = EyeAnimation.at(
                phase: Double(index - 1) * Self.spec.beat + Self.spec.beat * 0.9, spec: Self.spec)
            #expect(during.gaze == before.gaze)
        }
    }

    @Test("dart runs at twice the tempo of wander")
    func dartIsFaster() {
        var wander = Self.spec; wander.gaze = .wander
        var dart = Self.spec; dart.gaze = .dart
        func changes(_ spec: EyeSpec) -> Int {
            var count = 0
            var last = EyeAnimation.at(phase: 0, spec: spec).beat
            for step in 1..<1000 {
                let beat = EyeAnimation.at(phase: Double(step) * 0.01, spec: spec).beat
                if beat != last { count += 1; last = beat }
            }
            return count
        }
        #expect(changes(dart) > changes(wander))
    }

    @Test("numbers blend across a morph, the shape flips")
    func posesInterpolate() {
        let a = EyePose(eye: FaceFeature(shape: .oval, width: 6, height: 10, radius: 3), gap: 8)
        let b = EyePose(
            eye: FaceFeature(shape: .x, width: 10, height: 4, radius: 2, tilt: 16), gap: 6,
            mouth: FaceFeature(shape: .arc, width: 12, height: 5))
        #expect(EyePose.lerp(a, b, 0) == a)
        #expect(EyePose.lerp(a, b, 1) == b)
        let half = EyePose.lerp(a, b, 0.5)
        #expect(half.eye.width == 8)
        #expect(half.eye.height == 7)
        #expect(half.eye.shape == .x)
        #expect(EyePose.lerp(a, b, 0.4).eye.shape == .oval)
        // A mouth that appears takes its final form straight away rather than
        // growing out of nothing.
        #expect(EyePose.lerp(a, b, 0.1).mouth == b.mouth)
        // Clamped, not extrapolated: a pose past the target would invert the
        // tilt halfway through a morph.
        #expect(EyePose.lerp(a, b, 2) == b)
        #expect(EyePose.lerp(a, b, -1) == a)
    }
}

@Suite("Eyes: rasterisation to whole pixels")
@MainActor
struct EyesRasterTests {

    static let plateSize = CGSize(width: 58, height: 28)

    static func face(
        _ shape: EyeShape, w: CGFloat = 13, h: CGFloat = 12,
        r: CGFloat = 4, t: CGFloat = 0.35, bend: CGFloat = 0, tilt: CGFloat = 0,
        gap: CGFloat = 8, mouth: FaceFeature? = nil
    ) -> EyePose {
        EyePose(
            eye: FaceFeature(
                shape: shape, width: w, height: h, radius: r,
                thickness: t, bend: bend, tilt: tilt, offsetY: -4),
            gap: gap, mouth: mouth)
    }

    static func grid(_ pose: EyePose, _ animation: EyeAnimation = EyeAnimation()) -> [CGRect] {
        EyeRaster.cells(in: plateSize, pose: pose, animation: animation, pitch: 2)
    }

    static var axis: CGFloat { EyeRaster.cellCentre(plateSize.width / 2, pitch: 2) }
    static var middle: CGFloat { EyeRaster.cellCentre(plateSize.height / 2, pitch: 2) }

    /// Where the left eye's centre lands, so a test can probe around it.
    static func leftEye(_ pose: EyePose) -> CGPoint {
        CGPoint(
            x: axis - EyeRaster.quantise(pose.gap / 2 + pose.eye.width / 2, to: 2),
            y: middle + EyeRaster.quantise(pose.eye.offsetY, to: 2))
    }

    @Test("cells are whole, aligned, and inside the plate")
    func cellsAreWholePixels() {
        let cells = Self.grid(Self.face(.oval))
        #expect(!cells.isEmpty)
        for cell in cells {
            #expect(cell.width == 2 && cell.height == 2)
            #expect(cell.minX.truncatingRemainder(dividingBy: 2) == 0)
            #expect(cell.minY.truncatingRemainder(dividingBy: 2) == 0)
            #expect(cell.minX >= 0 && cell.maxX <= Self.plateSize.width)
            #expect(cell.minY >= 0 && cell.maxY <= Self.plateSize.height)
        }
    }

    @Test("a shut eye is a line, never nothing")
    func shutEyeStaysVisible() {
        var frame = EyeAnimation()
        frame.openness = 0
        let cells = Self.grid(Self.face(.oval), frame)
        #expect(!cells.isEmpty)
        #expect(Set(cells.map(\.minY)).count <= 2)
    }

    @Test("a blink shuts the eyes and leaves the mouth alone")
    func blinkSparesTheMouth() {
        let mouth = FaceFeature(shape: .oval, width: 10, height: 6, radius: 3, offsetY: 7)
        let pose = Self.face(.oval, mouth: mouth)
        var shut = EyeAnimation()
        shut.openness = 0
        let mouthBand = Self.middle + 7
        func mouthCells(_ frame: EyeAnimation) -> Int {
            Self.grid(pose, frame).filter { abs($0.midY - mouthBand) <= 4 }.count
        }
        #expect(mouthCells(shut) > 0)
        #expect(mouthCells(shut) == mouthCells(EyeAnimation()))
    }

    @Test("both eyes are drawn, and an asymmetric shape is mirrored")
    func twoMirroredEyes() {
        let cells = Self.grid(Self.face(.wing, bend: 1))
        func key(_ dx: CGFloat, _ y: CGFloat) -> String { "\(dx)|\(y)" }
        // The mirror axis is the snapped plate centre, not width / 2: the whole
        // point of snapping is that the geometry lands on the grid.
        let left = Set(cells.filter { $0.midX < Self.axis }.map { key(Self.axis - $0.midX, $0.midY) })
        let right = Set(cells.filter { $0.midX > Self.axis }.map { key($0.midX - Self.axis, $0.midY) })
        #expect(!left.isEmpty && !right.isEmpty)
        #expect(left == right, "eyes are not mirrored")
    }

    @Test("a ring is hollow, with a pupil")
    func ringIsHollow() {
        let pose = Self.face(.ring, w: 14, h: 14, t: 0.3)
        let cells = Self.grid(pose)
        let eye = Self.leftEye(pose)
        func lit(_ dx: CGFloat, _ dy: CGFloat) -> Bool {
            cells.contains { $0.contains(CGPoint(x: eye.x + dx, y: eye.y + dy)) }
        }
        // Probes in points on a 14 pt eye: the wall runs from 0.7 to 1.0 of the
        // half-width (4.9–7 pt), the pupil out to 0.255 (1.8 pt), and the gap
        // between them is what a ring has and a disc does not.
        #expect(lit(0, 0), "no pupil")
        #expect(lit(-6, 0) || lit(-5, 0), "no left wall")
        #expect(lit(6, 0) || lit(5, 0), "no right wall")
        #expect(!lit(-3, 0), "the ring should be hollow between pupil and wall")
    }

    @Test("an arc opens the way its bend says")
    func arcBends() {
        func lowestMiddle(_ bend: CGFloat) -> CGFloat {
            let pose = Self.face(.arc, w: 16, h: 10, t: 0.3, bend: bend)
            let eye = Self.leftEye(pose)
            let column = Self.grid(pose).filter { abs($0.midX - eye.x) <= 1 }
            return column.map { $0.midY }.min() ?? 0
        }
        // A smile's middle sits lower than a frown's; y grows downwards.
        #expect(lowestMiddle(1) > lowestMiddle(-1))
    }

    @Test("a line is a single bar")
    func lineIsABar() {
        let rows = Set(Self.grid(Self.face(.line, h: 3, t: 0.9)).map(\.minY))
        #expect(!rows.isEmpty)
        #expect(rows.count <= 2, "a line should not be \(rows.count) rows deep")
    }

    @Test("dots are three separated marks")
    func dotsAreThree() {
        let pose = Self.face(.dots, w: 16, h: 4, t: 0.18)
        let eye = Self.leftEye(pose)
        let columns = Self.grid(pose)
            .filter { abs($0.midX - eye.x) <= 9 && abs($0.midY - eye.y) <= 3 }
            .map(\.minX)
        // Three marks means at least two gaps in the run of columns.
        let sorted = Set(columns).sorted()
        let gaps = zip(sorted, sorted.dropFirst()).filter { $1 - $0 > 2 }.count
        #expect(gaps >= 2, "dots ran together: \(sorted)")
    }

    @Test("no look ever pushes an eye off the plate")
    func gazeStaysOnThePlate() throws {
        let manifest = EveFixture.manifest
        let plate = manifest.face
        let size = CGSize(width: plate.width, height: plate.height)
        for name in BuddyExpression.allCases {
            guard let spec = manifest.expressions[name.rawValue]?.eye else { continue }
            for step in 0..<1200 {
                let phase = Double(step) * 0.05
                let frame = EyeAnimation.at(phase: phase, spec: spec)
                let cells = EyeRaster.cells(
                    in: size, pose: spec.pose, animation: frame, pitch: 2)
                #expect(!cells.isEmpty, "\(name) went blank at \(phase)")
                for cell in cells {
                    #expect(cell.minX >= 0 && cell.maxX <= size.width, "\(name) at \(phase)")
                    #expect(cell.minY >= 0 && cell.maxY <= size.height, "\(name) at \(phase)")
                }
            }
        }
    }

    @Test("a degenerate plate draws nothing rather than trapping")
    func degenerateIsEmpty() {
        #expect(EyeRaster.cells(
            in: .zero, pose: Self.face(.oval), animation: EyeAnimation(), pitch: 2).isEmpty)
        #expect(EyeRaster.cells(
            in: Self.plateSize, pose: Self.face(.oval), animation: EyeAnimation(),
            pitch: 0).isEmpty)
    }
}
