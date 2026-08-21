import CoreGraphics
import Foundation

/// What a facial feature is drawn as. A closed vocabulary, like `MotionKind`:
/// a manifest picks one, it never describes one.
///
/// The shapes exist because parameters were not enough. An earlier pass drew
/// every state as one rounded box bent by a number; a ring, a wing and a smile
/// are not a rounded box at any value of any number, and at seven cells across
/// a bent box reads as a bent box.
public enum EyeShape: String, Sendable, Equatable, CaseIterable, Codable {
    /// Filled rounded rectangle — the neutral eye, and a flat mouth.
    case oval
    /// A crescent. `bend` decides which way it opens: positive smiles.
    case arc
    /// An annulus with a pupil at its centre. Hollow, and it reads that way.
    case ring
    /// A filled eye: a dim body, a bright iris ring, a bright pupil. What
    /// `ring` should have been — a hollow circle staring out of a dark screen
    /// is not an eye, it is a hole.
    case iris
    /// A tapered slash, thick at the outer end. The angry brow.
    case wing
    /// A single bar.
    case line
    /// Three cells in a row — the "…" between two working eyes.
    case dots
    /// `^`, two strokes meeting at the top.
    case caret
    /// `x`, two crossed strokes.
    case x
}

/// One drawn feature: a shape and the numbers that size it. Every number
/// interpolates, which is what buys the morph between expressions.
/// See RFC-005, "Notes d'implémentation".
public struct FaceFeature: Sendable, Equatable, Codable {
    public var shape: EyeShape = .oval
    /// Full width and height, in points.
    public var width: CGFloat = 9
    public var height: CGFloat = 13
    /// Corner radius, for `.oval` only, in points.
    public var radius: CGFloat = 4
    /// Stroke width for every other shape, as a fraction of the half-size.
    public var thickness: CGFloat = 0.35
    /// Which way an `arc` opens, and which way a `wing` slants.
    public var bend: CGFloat = 0
    /// Degrees, **mirrored** between the left and right copy of a feature.
    public var tilt: CGFloat = 0
    /// Distance from the middle of the plate, in points. Negative is up.
    public var offsetY: CGFloat = 0

    public init(
        shape: EyeShape = .oval, width: CGFloat = 9, height: CGFloat = 13,
        radius: CGFloat = 4, thickness: CGFloat = 0.35, bend: CGFloat = 0,
        tilt: CGFloat = 0, offsetY: CGFloat = 0
    ) {
        self.shape = shape; self.width = width; self.height = height
        self.radius = radius; self.thickness = thickness; self.bend = bend
        self.tilt = tilt; self.offsetY = offsetY
    }

    /// Numbers blend; the shape does not. Half of a ring and a crescent is
    /// neither, so the shape flips at the midpoint and the sizes carry the
    /// movement across.
    /// Every length multiplied, angles and fractions left alone. `thickness`
    /// and `bend` are ratios of the feature's own box, so they scale with it
    /// for free; multiplying them would thicken a shrinking face.
    public func scaled(_ k: CGFloat) -> FaceFeature {
        var out = self
        out.width *= k; out.height *= k
        out.radius *= k; out.offsetY *= k
        return out
    }

    public static func lerp(_ a: FaceFeature, _ b: FaceFeature, _ t: CGFloat) -> FaceFeature {
        let k = max(0, min(1, t))
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * k }
        return FaceFeature(
            shape: k < 0.5 ? a.shape : b.shape,
            width: mix(a.width, b.width), height: mix(a.height, b.height),
            radius: mix(a.radius, b.radius), thickness: mix(a.thickness, b.thickness),
            bend: mix(a.bend, b.bend), tilt: mix(a.tilt, b.tilt),
            offsetY: mix(a.offsetY, b.offsetY))
    }
}

/// A whole face: the eye, drawn twice and mirrored, and an optional mouth.
public struct EyePose: Sendable, Equatable, Codable {
    public var eye: FaceFeature
    /// Gap between the two eyes, in points.
    public var gap: CGFloat
    /// Absent for a face that is only eyes.
    public var mouth: FaceFeature?

    public init(
        eye: FaceFeature = FaceFeature(), gap: CGFloat = 14, mouth: FaceFeature? = nil
    ) {
        self.eye = eye; self.gap = gap; self.mouth = mouth
    }

    public func scaled(_ k: CGFloat) -> EyePose {
        EyePose(eye: eye.scaled(k), gap: gap * k, mouth: mouth?.scaled(k))
    }

    public static func lerp(_ a: EyePose, _ b: EyePose, _ t: CGFloat) -> EyePose {
        let k = max(0, min(1, t))
        // A mouth that appears mid-morph starts from the shape it is becoming
        // rather than from nothing: growing one out of a zero-sized feature
        // reads as a glitch, not as a face opening its mouth.
        let mouth: FaceFeature?
        switch (a.mouth, b.mouth) {
        case let (from?, to?): mouth = FaceFeature.lerp(from, to, k)
        case (nil, let to?):   mouth = k <= 0 ? nil : to
        case (let from?, nil): mouth = k < 0.5 ? from : nil
        case (nil, nil):       mouth = nil
        }
        return EyePose(
            eye: FaceFeature.lerp(a.eye, b.eye, k),
            gap: a.gap + (b.gap - a.gap) * k,
            mouth: mouth)
    }
}

/// Where the eyes are pointed. One of five places — never anywhere in between.
public enum EyeBeat: String, Sendable, Equatable, CaseIterable, Codable {
    case ahead, left, right, up, down
    /// Leaning in and pulling back. Not a look — a shift in depth, which the
    /// raster renders as the whole face growing or shrinking and the eyes
    /// setting wider or narrower apart.
    case near, far
    /// Narrowing the eyes without moving them: concentrating harder.
    case squint
    /// Sizing you up: one eye narrows further than the other and the face
    /// leans in a little, while the gaze stays straight at you. The asymmetry
    /// used to happen only as a by-product of the perspective on a sideways
    /// look; this makes it a pose the face can hold.
    case peerLeft, peerRight
    /// Looking up and off to one side, the way you look back over a shoulder.
    /// The head rolls with it, so the eye on the side being looked towards
    /// rides higher than the other one.
    case overLeft, overRight
    case blink
}

/// Which places an expression is allowed to look. A repertoire, not a speed.
public enum GazeKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// Stares ahead. Blinks still happen.
    case none
    /// The full repertoire.
    case wander
    /// Left and right only — reads as reading something.
    case scan
    /// The full repertoire at twice the tempo.
    case dart
    /// Looks nowhere, but leans in and pulls back. A face that is pleased with
    /// itself and has nothing left to look for.
    case calm
    /// Up, and up again. Someone who has been waiting a while.
    case bored

    /// `ahead` alternates with the directions on purpose, and the list is
    /// deliberately even in length: the step taken through it is always odd, so
    /// the eyes cannot land twice running on the same entry, and half the beats
    /// are spent looking straight ahead. An eye that visits a new corner every
    /// beat reads as a fault, not as a look.
    var repertoire: [EyeBeat] {
        switch self {
        case .none:   return [.ahead]
        case .calm:   return [.ahead, .near, .ahead, .far]
        case .bored:
            // Half the looks are upwards. The list alternates, and the walk
            // through it takes an odd step, so an `ahead` always falls between
            // two of them — four `up` entries never come out as a stare.
            return [.ahead, .up, .ahead, .up, .ahead, .left,
                    .ahead, .up, .ahead, .right, .ahead, .up,
                    .ahead, .down, .ahead, .far]
        case .scan:
            // Mostly side to side — it is meant to read as reading — but it
            // still looks up and down now and then, and leans in.
            return [.ahead, .left, .ahead, .right, .ahead, .squint,
                    .ahead, .left, .ahead, .right, .ahead, .up,
                    .ahead, .squint, .ahead, .down, .ahead, .near, .ahead, .far,
                    .ahead, .overLeft, .ahead, .overRight]
        case .wander, .dart:
            return [.ahead, .left, .ahead, .right, .ahead, .up,
                    .ahead, .down, .ahead, .near, .ahead, .far,
                    .ahead, .overLeft, .ahead, .overRight,
                    .ahead, .peerLeft, .ahead, .peerRight]
        }
    }

    /// Multiplier on the expression's beat.
    var tempo: Double { self == .dart ? 0.5 : 1 }
}

/// The animated half of an expression: the still face, plus the sequence of
/// beats played over it.
public struct EyeSpec: Sendable, Equatable, Codable {
    public var pose: EyePose
    /// Seconds one beat holds. The eyes are *still* for the whole beat and then
    /// somewhere else on the next one — there is no travel between them, and
    /// that is what makes the movement read as sharp rather than as drift.
    public var beat: Double
    /// Share of beats that are a blink instead of a look, 0…1. `0` never blinks.
    public var blink: Double
    public var gaze: GazeKind
    /// Multiplier on how far the face leans in and out. `0` never moves in
    /// depth, `1` is the default amount, above exaggerates it.
    public var depthScale: CGFloat
    /// What a beat actually lasts. Not `beat`: `dart` runs the same repertoire
    /// at twice the tempo, so the two differ by a factor of two there — and a
    /// caller that samples on `beat` alone lands on a different beat than the
    /// one it asked about.
    public var beatLength: Double { max(EyeSpec.minimumBeat, beat * gaze.tempo) }

    /// Share of dark cells the digital grain lights faintly, 0…1.
    public var grain: Double
    /// How badly the picture tears, 0…1. `0` is a screen that is working.
    public var glitch: Double

    public init(
        pose: EyePose, beat: Double = 0.62, blink: Double = 0.3, gaze: GazeKind = .wander,
        depthScale: CGFloat = 1, grain: Double = 0.03, glitch: Double = 0
    ) {
        self.pose = pose; self.beat = beat; self.blink = blink; self.gaze = gaze
        self.depthScale = depthScale; self.grain = grain; self.glitch = glitch
    }

    /// Ticks per second for the grain and the tear. Slower than the clock on
    /// purpose: noise that changes on every frame makes the whole path change
    /// on every frame, and the face itself only moves every second or two.
    public static let noiseRate: Double = 3

    /// How long the lid stays shut, in **seconds** — not a share of the beat.
    /// The two were tied at first, so slowing the eyes down to stop them
    /// twitching also slowed the blink into an eye closing. A blink reads right
    /// at about a quarter of a second whatever the tempo around it.
    public static let blinkDuration: Double = 0.23

    /// How long the eyes take to cross from one look to the next.
    ///
    /// Fast is not the same as instant. The first version snapped between two
    /// positions with nothing in between, and at a two-point grid that reads as
    /// the picture cutting rather than as an eye moving. A quarter of a second
    /// is still a saccade — it is roughly what a real one takes — and at 8 Hz
    /// it leaves two or three intermediate cells, which is exactly how a
    /// pixel-art eye should travel.
    public static let saccade: Double = 0.26

    /// How far a look travels, as a fraction of the eye's own size.
    ///
    /// It went 1.4 → 0.32 → 0.95. At 1.4 the eyes crossed most of the plate and
    /// left the mouth — which does not move — sitting under one of them; at
    /// 0.32 they moved two cells, which the perspective then half swallowed.
    /// The mouth is gone and the screen has room for five cells. What actually
    /// stops the eye at the edge is the clamp in `EyeRaster`, which measures
    /// the frame rather than trusting a constant here.
    static let reachX: CGFloat = 0.95
    /// Vertical reach used to be 0.22, which on a 15 pt eye came to three
    /// points — one cell, and one cell is not a look upwards, it is a rounding
    /// error. The plate has room for three.
    static let reachY: CGFloat = 0.42

    /// How much further the narrowed eye closes than its neighbour when the
    /// face is sizing you up.
    static let lopsided: CGFloat = 0.42
    /// The small lean-in that comes with it. Much less than `nearer`: this is
    /// scrutiny, not a face pressed against the glass.
    static let peering: CGFloat = 1.06

    /// How far apart the two eyes ride when the head rolls, as a fraction of
    /// the eye's height. It is the whole of what makes a glance over the
    /// shoulder read as one: the same offset applied to both eyes is a look
    /// upwards, and one eye higher than the other is a head that turned.
    static let roll: CGFloat = 0.30

    /// How far the eyes close down when concentrating. Not a blink: it holds
    /// for the whole beat, and the eyes stay where they were looking.
    static let squinted: CGFloat = 0.52

    /// How much bigger a face gets when it leans in, and smaller when it pulls
    /// back. Small on purpose: past about a sixth it stops reading as depth and
    /// starts reading as the whole screen zooming. An expression can ask for
    /// more or less of it through `depth:`.
    static let nearer: CGFloat = 1.13
    static let further: CGFloat = 0.91

    public static let minimumBeat: Double = 0.08
    public static let maximumBeat: Double = 10
}

/// Everything time-dependent, as one pure function of the phase. No state, no
/// `Task`, no `repeatForever`: the single `TimelineView` of `BuddyView` hands it
/// a phase and gets back a picture (D3).
public struct EyeAnimation: Sendable, Equatable {
    public var beat: EyeBeat = .ahead
    /// 0 = shut, 1 = the pose's own height. Applies to the eyes only — a blink
    /// that shut the mouth as well would read as the whole face switching off.
    public var openness: CGFloat = 1
    /// Cartoon volume: what the lid takes in height, the eye takes back in width.
    public var stretch: CGFloat = 1
    /// Smear along the direction of travel — the eye stretches into the move
    /// and settles out of it. One frame of squash is what separates a thing
    /// that moved from a thing that was redrawn somewhere else.
    public var smear: CGSize = CGSize(width: 1, height: 1)
    public var gaze: CGSize = .zero
    /// 1 is where the face sits; above is leaning in, below is pulled back.
    public var depth: CGFloat = 1
    /// Below 1 when the eyes narrow to concentrate.
    public var squeeze: CGFloat = 1
    /// Points the **left** eye rides above the right. Negative is the other way.
    public var roll: CGFloat = 0
    /// How much further the **left** eye is closed than the right, 0…1.
    /// Negative closes the right one instead.
    public var lopsided: CGFloat = 0

    public static func at(phase: Double, spec: EyeSpec) -> EyeAnimation {
        var animation = EyeAnimation()
        let beatLength = spec.beatLength
        guard phase >= 0, beatLength > 0 else { return animation }

        let index = Int((phase / beatLength).rounded(.down))
        animation.beat = beat(at: index, spec: spec)

        if animation.beat == .blink {
            let within = phase - Double(index) * beatLength
            // Binary, not eased. An eased lid is what "ça bouge trop" was: at
            // this size a ramp is one grey frame, and one grey frame reads as a
            // smear rather than as a snap.
            animation.openness = within < EyeSpec.blinkDuration ? 0 : 1
        }
        animation.stretch = 1 + 0.26 * (1 - animation.openness)

        let previous = beat(at: index - 1, spec: spec)
        let older = beat(at: index - 2, spec: spec)
        let target = offset(for: animation.beat, eye: spec.pose.eye, previous: previous)
        let from = offset(for: previous, eye: spec.pose.eye, previous: older)
        let targetDepth = depth(for: animation.beat, previous: previous, scale: spec.depthScale)
        let fromDepth = depth(for: previous, previous: older, scale: spec.depthScale)
        let targetSqueeze = squeeze(for: animation.beat, previous: previous)
        let fromSqueeze = squeeze(for: previous, previous: older)
        let targetRoll = roll(for: animation.beat, eye: spec.pose.eye, previous: previous)
        let fromRoll = roll(for: previous, eye: spec.pose.eye, previous: older)
        let targetLopsided = lopsided(for: animation.beat, previous: previous)
        let fromLopsided = lopsided(for: previous, previous: older)
        let within = phase - Double(index) * beatLength
        let crossing = min(1, max(0, within / min(EyeSpec.saccade, beatLength)))

        if (target == from && targetDepth == fromDepth && targetSqueeze == fromSqueeze
            && targetRoll == fromRoll && targetLopsided == fromLopsided)
            || crossing >= 1 {
            animation.gaze = target
            animation.depth = targetDepth
            animation.squeeze = targetSqueeze
            animation.roll = targetRoll
            animation.lopsided = targetLopsided
        } else {
            // Ease out with a little overshoot: the eye arrives, goes one step
            // past, and settles. That last step is most of what reads as alive.
            let eased = CGFloat(overshoot(crossing))
            animation.gaze = CGSize(
                width: from.width + (target.width - from.width) * eased,
                height: from.height + (target.height - from.height) * eased)
            animation.depth = fromDepth + (targetDepth - fromDepth) * eased
            animation.squeeze = fromSqueeze + (targetSqueeze - fromSqueeze) * eased
            animation.roll = fromRoll + (targetRoll - fromRoll) * eased
            animation.lopsided = fromLopsided + (targetLopsided - fromLopsided) * eased
            // Smear along the travel, strongest at the start of the crossing.
            let intensity = CGFloat((1 - crossing) * 0.32)
            let dx = abs(target.width - from.width)
            let dy = abs(target.height - from.height)
            let total = max(dx + dy, 0.001)
            animation.smear = CGSize(
                width: 1 + intensity * (dx / total),
                height: 1 + intensity * (dy / total))
        }
        return animation
    }

    /// The beat at `index`: a blink, or one of the looks in the repertoire.
    ///
    /// Deterministic by construction, which is the point: `Double.random` needs
    /// state, state needs a `Task`, and a `Task` is what D3 forbids.
    ///
    /// The eyes never land on the same look twice running; see `rawPick` for
    /// how that is a property of the walk rather than a check.
    public static func beat(at index: Int, spec: EyeSpec) -> EyeBeat {
        guard index >= 0 else { return .ahead }
        if isBlink(at: index, spec: spec) { return .blink }
        let repertoire = spec.gaze.repertoire
        guard repertoire.count > 1 else { return repertoire.first ?? .ahead }
        return repertoire[rawPick(at: index, count: repertoire.count)]
    }

    static func isBlink(at index: Int, spec: EyeSpec) -> Bool {
        guard index >= 0, spec.blink > 0 else { return false }
        return hashed01(index, salt: 0x51ED) < min(1, spec.blink)
    }

    /// How far apart two looks may be and still be compared. Beyond it the
    /// walk restarts, which is what keeps this O(1) instead of unwinding to
    /// beat zero on every frame.
    static let blockLength = 64

    /// Which entry of the repertoire beat `index` lands on.
    ///
    /// A running walk rather than a direct hash: the step is drawn from the
    /// hash but is always **odd**, and the repertoire alternates `ahead` with a
    /// direction, so an odd step always changes which of the two it is. That
    /// makes "never the same look twice running" a property of the
    /// construction rather than a comparison that has to be re-derived — the
    /// comparison version had to look at the previous beat, which made the
    /// function recursive and then made it disagree with itself.
    ///
    /// The walk restarts every `blockLength` beats from a hash of the block, so
    /// it stays O(1). One repeat is possible at each restart, about once every
    /// hundred seconds, which is under the threshold at which a repeat is even
    /// visible.
    static func rawPick(at index: Int, count: Int) -> Int {
        guard count > 1, index >= 0 else { return 0 }
        let anchor = (index / blockLength) * blockLength
        var position = Int(hashed01(anchor, salt: 0xC0FE) * Double(count)) % count
        guard anchor < index else { return position }
        let half = max(1, count / 2)
        for step in (anchor + 1)...index {
            let odd = 1 + 2 * min(half - 1, Int(hashed01(step, salt: 0xA17E) * Double(half)))
            position = (position + odd) % count
        }
        return position
    }

    /// Ease-out with a single overshoot past the target.
    static func overshoot(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let u = t - 1
        // The classic back-out constants, tamed: a full 1.70158 sends the eye
        // a third of the way past the target, which on a plate this size means
        // straight off the edge.
        let c = 0.9
        return 1 + (c + 1) * u * u * u + c * u * u
    }

    /// A blink holds whatever the previous beat was looking at, so the eyes do
    /// not jump back to centre just to close.
    static func offset(for beat: EyeBeat, eye: FaceFeature, previous: EyeBeat) -> CGSize {
        let effective = beat == .blink ? (previous == .blink ? .ahead : previous) : beat
        let dx = eye.width * EyeSpec.reachX
        let dy = eye.height * EyeSpec.reachY
        switch effective {
        case .ahead, .blink, .near, .far, .squint, .peerLeft, .peerRight: return .zero
        case .left:      return CGSize(width: -dx, height: 0)
        case .right:     return CGSize(width: dx, height: 0)
        case .up:        return CGSize(width: 0, height: -dy)
        case .down:      return CGSize(width: 0, height: dy)
        // Off to the side *and* up — a glance over the shoulder goes both ways
        // at once, and never quite as far sideways as a straight look.
        case .overLeft:  return CGSize(width: -dx * 0.75, height: -dy * 0.8)
        case .overRight: return CGSize(width: dx * 0.75, height: -dy * 0.8)
        }
    }

    /// A blink holds the depth it interrupted, for the same reason it holds the
    /// look: closing the eyes is not a reason to move the head.
    /// How much further the left eye is closed than the right.
    static func lopsided(for beat: EyeBeat, previous: EyeBeat) -> CGFloat {
        let effective = beat == .blink ? (previous == .blink ? .ahead : previous) : beat
        switch effective {
        case .peerLeft:  return EyeSpec.lopsided
        case .peerRight: return -EyeSpec.lopsided
        default:         return 0
        }
    }

    /// How far the left eye rides above the right. A blink holds it, like
    /// everything else it interrupts.
    static func roll(for beat: EyeBeat, eye: FaceFeature, previous: EyeBeat) -> CGFloat {
        let effective = beat == .blink ? (previous == .blink ? .ahead : previous) : beat
        let amount = eye.height * EyeSpec.roll
        switch effective {
        case .overLeft:  return -amount
        case .overRight: return amount
        default:         return 0
        }
    }

    /// A blink holds the squint it interrupted, for the same reason it holds
    /// the look.
    static func squeeze(for beat: EyeBeat, previous: EyeBeat) -> CGFloat {
        let effective = beat == .blink ? (previous == .blink ? .ahead : previous) : beat
        return effective == .squint ? EyeSpec.squinted : 1
    }

    static func depth(for beat: EyeBeat, previous: EyeBeat, scale: CGFloat) -> CGFloat {
        let effective = beat == .blink ? (previous == .blink ? .ahead : previous) : beat
        switch effective {
        case .near: return 1 + (EyeSpec.nearer - 1) * max(0, scale)
        case .far:  return 1 + (EyeSpec.further - 1) * max(0, scale)
        case .peerLeft, .peerRight: return EyeSpec.peering
        default:    return 1
        }
    }
}

/// splitmix64 on the beat index.
func hashed01(_ n: Int, salt: UInt64) -> Double {
    var x = UInt64(bitPattern: Int64(n)) &+ (salt &* 0x9E37_79B9_7F4A_7C15)
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x = x ^ (x >> 31)
    return Double(x >> 11) / Double(UInt64(1) << 53)
}
