import CoreGraphics
import Foundation

/// What a facial feature is drawn as.
public enum EyeShape: String, Sendable, Equatable, CaseIterable, Codable {
    /// Filled rounded rectangle — the neutral eye, and a flat mouth.
    case oval
    /// A crescent.
    case arc
    /// An annulus with a pupil at its centre.
    case ring
    /// A filled eye: a dim body, a bright iris ring, a bright pupil.
    case iris
    /// A tapered slash, thick at the outer end.
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

/// One drawn feature: a shape and the numbers that size it.
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
    /// Degrees, mirrored between the left and right copy of a feature.
    public var tilt: CGFloat = 0
    /// Distance from the middle of the plate, in points.
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

    /// Numbers blend; the shape does not.
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
        // A mouth that appears mid-morph starts from the shape it is becoming rather
        // than from nothing: growing one out of a zero-sized feature reads as a glitch,
        // not as a face opening its mouth.
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

/// Where the eyes are pointed.
public enum EyeBeat: String, Sendable, Equatable, CaseIterable, Codable {
    case ahead, left, right, up, down
    /// Leaning in and pulling back.
    case near, far
    /// Narrowing the eyes without moving them: concentrating harder.
    case squint
    /// Sizing you up: one eye narrows further than the other and the face leans in a
    /// little, while the gaze stays straight at you.
    case peerLeft, peerRight
    /// Looking up and off to one side, the way you look back over a shoulder.
    case overLeft, overRight
    case blink
}

/// Which places an expression is allowed to look.
public enum GazeKind: String, Sendable, Equatable, CaseIterable, Codable {
    /// Stares ahead.
    case none
    /// The full repertoire.
    case wander
    /// Left and right only — reads as reading something.
    case scan
    /// The full repertoire at twice the tempo.
    case dart
    /// Looks nowhere, but leans in and pulls back.
    case calm
    /// Up, and up again.
    case bored

    /// `ahead` alternates with the directions on purpose, and the list is deliberately
    /// even in length: the step taken through it is always odd, so the eyes cannot land
    /// twice running on the same entry, and half the beats are spent looking straight
    /// ahead.
    var repertoire: [EyeBeat] {
        switch self {
        case .none:   return [.ahead]
        case .calm:   return [.ahead, .near, .ahead, .far]
        case .bored:
            // Half the looks are upwards.
            return [.ahead, .up, .ahead, .up, .ahead, .left,
                    .ahead, .up, .ahead, .right, .ahead, .up,
                    .ahead, .down, .ahead, .far]
        case .scan:
            // Mostly side to side — it is meant to read as reading — but it still looks
            // up and down now and then, and leans in.
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

/// The animated half of an expression: the still face, plus the sequence of beats played
/// over it.
public struct EyeSpec: Sendable, Equatable, Codable {
    public var pose: EyePose
    /// Seconds one beat holds.
    public var beat: Double
    /// Share of beats that are a blink instead of a look, 0…1.
    public var blink: Double
    public var gaze: GazeKind
    /// Multiplier on how far the face leans in and out.
    public var depthScale: CGFloat
    /// What a beat actually lasts.
    public var beatLength: Double { max(EyeSpec.minimumBeat, beat * gaze.tempo) }

    /// Share of dark cells the digital grain lights faintly, 0…1.
    public var grain: Double
    /// How badly the picture tears, 0…1.
    public var glitch: Double

    public init(
        pose: EyePose, beat: Double = 0.62, blink: Double = 0.3, gaze: GazeKind = .wander,
        depthScale: CGFloat = 1, grain: Double = 0.03, glitch: Double = 0
    ) {
        self.pose = pose; self.beat = beat; self.blink = blink; self.gaze = gaze
        self.depthScale = depthScale; self.grain = grain; self.glitch = glitch
    }

    /// Ticks per second for the grain and the tear.
    public static let noiseRate: Double = 3

    /// How long the lid stays shut, in seconds — not a share of the beat.
    public static let blinkDuration: Double = 0.23

    /// How long the eyes take to cross from one look to the next. A quarter of a second
    /// is still a saccade — it is roughly what a real one takes — and at 8 Hz it leaves
    /// two or three intermediate cells, which is exactly how a pixel-art eye should
    /// travel.
    public static let saccade: Double = 0.26

    /// How far a look travels, as a fraction of the eye's own size.
    static let reachX: CGFloat = 0.95
    /// It went 0.22 → 0.42 → 0.85. At 0.22, a 15 pt eye moved three points — one cell,
    /// which is a rounding error rather than a look upwards. What actually stops it now
    /// is not this number but the screen: `EyeRaster` keeps the whole eye inside, so an
    /// eye of height `h` on a 30 pt screen can rise at most `(30 - h) / 2`.
    static let reachY: CGFloat = 0.85

    /// How much further the narrowed eye closes than its neighbour when the face is
    /// sizing you up.
    static let lopsided: CGFloat = 0.42
    /// The small lean-in that comes with it.
    static let peering: CGFloat = 1.06

    /// How far apart the two eyes ride when the head rolls, as a fraction of the eye's
    /// height.
    static let roll: CGFloat = 0.30

    /// How far the eyes close down when concentrating.
    static let squinted: CGFloat = 0.52

    /// How much bigger a face gets when it leans in, and smaller when it pulls back.
    static let nearer: CGFloat = 1.13
    static let further: CGFloat = 0.91

    public static let minimumBeat: Double = 0.08
    public static let maximumBeat: Double = 10
}

/// Everything time-dependent, as one pure function of the phase.
public struct EyeAnimation: Sendable, Equatable {
    public var beat: EyeBeat = .ahead
    /// 0 = shut, 1 = the pose's own height.
    public var openness: CGFloat = 1
    /// Cartoon volume: what the lid takes in height, the eye takes back in width.
    public var stretch: CGFloat = 1
    /// Smear along the direction of travel — the eye stretches into the move and settles
    /// out of it.
    public var smear: CGSize = CGSize(width: 1, height: 1)
    public var gaze: CGSize = .zero
    /// 1 is where the face sits; above is leaning in, below is pulled back.
    public var depth: CGFloat = 1
    /// Below 1 when the eyes narrow to concentrate.
    public var squeeze: CGFloat = 1
    /// Points the left eye rides above the right.
    public var roll: CGFloat = 0
    /// How much further the left eye is closed than the right, 0…1.
    public var lopsided: CGFloat = 0

    public static func at(phase: Double, spec: EyeSpec) -> EyeAnimation {
        var animation = EyeAnimation()
        let beatLength = spec.beatLength
        guard phase >= 0, beatLength > 0 else { return animation }

        let index = Int((phase / beatLength).rounded(.down))
        animation.beat = beat(at: index, spec: spec)

        if animation.beat == .blink {
            let within = phase - Double(index) * beatLength
            // Binary, not eased.
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
            // Ease out with a little overshoot: the eye arrives, goes one step past,
            // and settles.
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

    /// How far apart two looks may be and still be compared.
    static let blockLength = 64

    /// Which entry of the repertoire beat `index` lands on.
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
        // The classic back-out constants, tamed: a full 1.70158 sends the eye a third
        // of the way past the target, which on a plate this size means straight off the
        // edge.
        let c = 0.9
        return 1 + (c + 1) * u * u * u + c * u * u
    }

    /// A blink holds whatever the previous beat was looking at, so the eyes do not jump
    /// back to centre just to close.
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
        // Off to the side *and* up — a glance over the shoulder goes both ways at once,
        // and never quite as far sideways as a straight look.
        case .overLeft:  return CGSize(width: -dx * 0.75, height: -dy * 0.8)
        case .overRight: return CGSize(width: dx * 0.75, height: -dy * 0.8)
        }
    }

    /// A blink holds the depth it interrupted, for the same reason it holds the look:
    /// closing the eyes is not a reason to move the head.
    static func lopsided(for beat: EyeBeat, previous: EyeBeat) -> CGFloat {
        let effective = beat == .blink ? (previous == .blink ? .ahead : previous) : beat
        switch effective {
        case .peerLeft:  return EyeSpec.lopsided
        case .peerRight: return -EyeSpec.lopsided
        default:         return 0
        }
    }

    /// How far the left eye rides above the right.
    static func roll(for beat: EyeBeat, eye: FaceFeature, previous: EyeBeat) -> CGFloat {
        let effective = beat == .blink ? (previous == .blink ? .ahead : previous) : beat
        let amount = eye.height * EyeSpec.roll
        switch effective {
        case .overLeft:  return -amount
        case .overRight: return amount
        default:         return 0
        }
    }

    /// A blink holds the squint it interrupted, for the same reason it holds the look.
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
