import CoreGraphics
import Foundation

/// What the buddy is doing about the pointer.
///
/// Deliberately a small closed set, like `EyeShape` and `MotionKind`: the face
/// is a repertoire, never a set of numbers a caller gets to invent.
public enum PointerMood: Sendable, Equatable {
    /// The manifest's own cycle. Nothing here overrides anything.
    case resting
    /// Caught the movement and is surprised by it, `progress` 0…1 through it.
    case startled(progress: Double)
    /// Tracking. `progress` runs 0…1 over the first moments, so the eyes
    /// arrive rather than snap.
    case following(progress: Double)
    /// Laughing: `^^`, hopping. `progress` 0…1 through the fit.
    ///
    /// `chasing` is set when the laugh happened *during* a chase: the chase
    /// keeps its colour through it, because it has not stopped — it is the same
    /// buddy, mid-chase, finding this funny.
    case amused(progress: Double, chasing: Bool)
    /// Dropped what it was doing to chase the pointer, and will keep chasing
    /// until the pointer stops. `progress` 0…1 as it winds up.
    case chasing(progress: Double)
}

/// What a shake gets, which depends on what the buddy was doing.
public enum ShakeResponse: String, Sendable, Equatable {
    /// A buddy with nothing to do finds it funny.
    case laugh
    /// A buddy that was working drops everything and gives chase.
    case chase
}

public extension PointerMood {
    /// The colour this mood insists on, over the manifest's own. Only the
    /// chase has one: it is the whole point of it being a mode rather than a
    /// look, and the buddy has visibly stopped working.
    var tint: String? {
        switch self {
        case .chasing: return "#FF5FA2"
        case let .amused(_, chasing): return chasing ? "#FF5FA2" : nil
        default: return nil
        }
    }

    /// How much of `tint` is showing, 0…1.
    ///
    /// The chase's own `progress`, so the colour arrives with the look and
    /// leaves with it. A tint that snapped on and off would read as the face
    /// being replaced rather than as the same face changing its mind.
    var tintStrength: Double {
        switch self {
        case let .chasing(progress): return progress
        // Full strength through a laugh mid-chase: the chase is still on, and
        // a colour that dipped for the joke would read as letting go.
        case let .amused(_, chasing): return chasing ? 1 : 0
        default: return 0
        }
    }

    /// Whether the face is doing something of its own rather than the
    /// manifest's cycle. Used to decide whether the clock must keep running.
    var isActive: Bool { self != .resting }

    /// An expression this mood borrows the *eyes* of, over whatever the buddy
    /// is currently wearing.
    ///
    /// Only the chase does, and it takes `finished`'s: wide and round, which is
    /// the face for having dropped everything to go after something. The
    /// working eyes are narrowed to concentrate, and a narrowed eye chasing a
    /// mouse reads as annoyance rather than as play. The colour stays the
    /// chase's own — see `tint`.
    var borrowedExpression: BuddyExpression? {
        switch self {
        case .chasing: return .finished
        // Laughing draws `^^` over whatever eyes it is wearing, so borrowing
        // through the laugh only matters for what comes back after it.
        case let .amused(_, chasing): return chasing ? .finished : nil
        default: return nil
        }
    }
}

/// Where the pointer sits on screen, as the face reads it.
///
/// Nine zones, not a continuous vector. The raster already quantises a look to
/// whole cells — `EyeRaster`'s own note says the look is one of five places —
/// so feeding it a smooth direction buys nothing but a value that rounds to the
/// same cell for a third of the screen. Reading the screen in bands makes the
/// rule sayable, and the face legible: you can tell where the buddy thinks you
/// are.
public struct PointerLook: Sendable, Equatable {
    /// −1 left, 0 centre, +1 right.
    public var x: CGFloat = 0
    /// −1 up, 0 level, +1 down.
    public var y: CGFloat = 0
    /// The head rolling with an over-the-shoulder glance: −1, 0 or +1.
    public var roll: CGFloat = 0

    public static let level = PointerLook()

    public init(x: CGFloat = 0, y: CGFloat = 0, roll: CGFloat = 0) {
        self.x = x; self.y = y; self.roll = roll
    }
}

/// Turns raw pointer positions into a mood.
///
/// A value type, and pure apart from the clock it is handed: everything here is
/// tested by feeding it positions and dates, with no run loop and no window
/// server. `PointerGaze` is the observable shell the views watch.
public struct PointerGazeState: Sendable, Equatable {

    // MARK: - Timings

    /// How long the pointer must keep moving before the buddy takes an
    /// interest. Without it, crossing the screen once to click something makes
    /// the face lurch — the movement has to look deliberate first.
    public static let noticeDelay: TimeInterval = 0.35
    /// The double-take, before tracking starts.
    public static let startleDuration: TimeInterval = 0.45
    /// How long the eyes take to reach the pointer once tracking starts.
    public static let catchUp: TimeInterval = 0.35
    /// Movement stopped for this long and the manifest takes over again.
    public static let restDelay: TimeInterval = 1.2
    /// Tracking this long without a break earns another double-take.
    public static let curiosityInterval: TimeInterval = 3.4
    /// How long the chase takes to let go once the pointer has stopped: the
    /// colour and the look ease back rather than cutting.
    public static let chaseFade: TimeInterval = 0.45
    /// How long a fit of laughter lasts.
    public static let amusementDuration: TimeInterval = 1.25
    /// What counts as being wiggled at, rather than as ordinary aiming.
    ///
    /// Three reversals in a window was far too easy: reaching for a button and
    /// correcting past it makes two or three, so the buddy laughed at people
    /// using their computer. A shake is **fast**, **repeated**, and **wide** —
    /// all three, or it is just a mouse going somewhere.
    public static let wiggleWindow: TimeInterval = 0.6
    public static let wiggleReversals = 5
    /// How far the pointer must travel one way before turning back for that
    /// turn to count. Below this, a reversal is a hand not being perfectly
    /// steady.
    public static let wiggleSwing: CGFloat = 24
    /// Below this, a "movement" is a hand resting on the trackpad.
    public static let movementThreshold: CGFloat = 1.5

    // MARK: - State

    /// Where the buddy's face is on screen. Empty disables everything.
    public var anchor: CGRect = .zero

    /// Whether an ordinary movement is worth looking at. False while the buddy
    /// is busy: it keeps working, and only a shake gets its attention.
    public var followsPointer = true
    /// What a shake earns.
    public var shakeMeans: ShakeResponse = .laugh
    /// The display the face is on. The bands below are read off this, so a
    /// second monitor of another size divides in the same places.
    public var screen: CGRect = .zero

    // MARK: - The bands

    /// Above this share of the screen's height, measured from the top, the
    /// pointer is high enough that the face looks up **over its shoulder**
    /// rather than merely up.
    public static let overShoulderBand: CGFloat = 0.25
    /// Below the middle of the screen, the eyes go down.
    public static let lowBand: CGFloat = 0.5
    /// Outer thirds are left and right; the middle third is straight ahead.
    public static let sideBand: CGFloat = 1.0 / 3

    private var last: CGPoint?
    private var lastMoveAt: Date?
    /// When the current run of movement began — reset by every pause.
    private var movingSince: Date?
    /// When the buddy last did a double-take, so it can do another.
    private var startledAt: Date?
    private var amusedUntil: Date?
    /// Set by a shake while `shakeMeans` is `.chase`, cleared by the pointer
    /// going quiet. The chase has no duration of its own — it lasts exactly as
    /// long as there is something to chase.
    private var chasingSince: Date?
    /// Sign of the last horizontal travel, and when the reversals happened.
    private var lastSign: CGFloat = 0
    private var reversals: [Date] = []
    /// How far the pointer has run since the last turn. A turn that ends a
    /// short run is not a turn, it is a wobble.
    private var swing: CGFloat = 0

    public init() {}

    // MARK: - Feeding it

    /// One pointer position. Called from an event monitor, so it is silent
    /// while the pointer is still — that is what keeps the resting wake budget
    /// at zero.
    public mutating func note(_ point: CGPoint, at now: Date) {
        defer { last = point }
        guard let previous = last else {
            lastMoveAt = now
            return
        }
        let dx = point.x - previous.x
        let dy = point.y - previous.y
        guard hypot(dx, dy) >= Self.movementThreshold else { return }

        // A pause long enough to rest ends the run: the next movement is a new
        // one, and gets its own double-take.
        if let since = lastMoveAt, now.timeIntervalSince(since) > Self.restDelay {
            movingSince = now
            startledAt = nil
            // The pointer stopped, so there is nothing left to chase.
            chasingSince = nil
            reversals.removeAll(keepingCapacity: true)
        } else if movingSince == nil {
            movingSince = now
        }
        lastMoveAt = now

        // Wiggling: the horizontal direction keeps flipping, and each leg of
        // the shake actually goes somewhere.
        let sign: CGFloat = dx > 0 ? 1 : (dx < 0 ? -1 : lastSign)
        if sign != 0, lastSign != 0, sign != lastSign {
            if swing >= Self.wiggleSwing {
                reversals.append(now)
                reversals.removeAll { now.timeIntervalSince($0) > Self.wiggleWindow }
                if reversals.count >= Self.wiggleReversals {
                    // One way in for laughter, whatever caused it — a shake
                    // here, a click from the panel, anything later.
                    switch shakeMeans {
                    case .laugh:
                        amuse(at: now)
                    case .chase:
                        // The first shake starts the chase; shaking at a buddy
                        // that is *already* chasing is a joke it gets.
                        if chasingSince == nil { chasingSince = now } else { amuse(at: now) }
                    }
                    reversals.removeAll(keepingCapacity: true)
                }
            } else {
                // A turn that came too soon breaks the run: five wobbles in a
                // row must not add up to a shake.
                reversals.removeAll(keepingCapacity: true)
            }
            swing = 0
        }
        swing += abs(dx)
        if sign != 0 { lastSign = sign }
    }

    // MARK: - Reading it

    public func mood(at now: Date) -> PointerMood {
        guard !anchor.isEmpty else { return .resting }

        // Laughter first, so a poke lands even mid-chase: the chase picks up
        // again the moment the laugh is over, since nothing about it was lost.
        if let until = amusedUntil, now < until {
            let elapsed = Self.amusementDuration - until.timeIntervalSince(now)
            let mid = chasingSince != nil && lastMoveAt.map {
                now.timeIntervalSince($0) <= Self.restDelay + Self.chaseFade
            } == true
            return .amused(progress: clamp(elapsed / Self.amusementDuration), chasing: mid)
        }

        // The chase outranks the rest. It winds up over `catchUp` and lets go
        // over `chaseFade` once the pointer stops — one number, `progress`,
        // running up and then back down, so the colour and the look ease in and
        // out together rather than each on its own clock.
        if let since = chasingSince, let lastMoveAt {
            let quiet = now.timeIntervalSince(lastMoveAt)
            if quiet <= Self.restDelay {
                return .chasing(progress: clamp(now.timeIntervalSince(since) / Self.catchUp))
            }
            let letting = 1 - (quiet - Self.restDelay) / Self.chaseFade
            if letting > 0 { return .chasing(progress: clamp(letting)) }
        }
        // A busy buddy keeps working. Only a shake — handled above — gets it
        // to look up.
        guard followsPointer else { return .resting }

        guard let lastMoveAt, now.timeIntervalSince(lastMoveAt) <= Self.restDelay,
              let movingSince
        else { return .resting }

        let run = now.timeIntervalSince(movingSince)
        guard run >= Self.noticeDelay else { return .resting }

        // The double-take: once when the run is first noticed, then again every
        // so often while it goes on — the buddy remembering to be surprised.
        let sinceStartle = startledAt.map { now.timeIntervalSince($0) }
        let startleBegan = sinceStartle == nil
            ? movingSince.addingTimeInterval(Self.noticeDelay)
            : (sinceStartle! >= Self.curiosityInterval ? now : startledAt!)
        let inStartle = now.timeIntervalSince(startleBegan)
        if inStartle >= 0, inStartle < Self.startleDuration {
            return .startled(progress: clamp(inStartle / Self.startleDuration))
        }

        let tracking = run - Self.noticeDelay - Self.startleDuration
        return .following(progress: clamp(max(0, tracking) / Self.catchUp))
    }

    /// Something funny happened — being poked, most likely.
    ///
    /// Separate from the shake: a click is unambiguous, so it needs none of the
    /// evidence a shake does, and it laughs whatever `shakeMeans` says.
    public mutating func amuse(at now: Date) {
        amusedUntil = now.addingTimeInterval(Self.amusementDuration)
    }

    /// Whether a chase is under way. Read by tests and by `--info`.
    public var isChasing: Bool { chasingSince != nil }

    /// Records that a double-take has been shown, so the next one is due later.
    /// Separate from `mood` because reading must not change what is read.
    public mutating func markStartled(at now: Date) {
        if let at = startledAt, now.timeIntervalSince(at) < Self.curiosityInterval { return }
        startledAt = now
    }

    /// Which of the nine zones the pointer is in, as a look.
    ///
    /// | | gauche | centre | droite |
    /// |---|---|---|---|
    /// | haut, 25 % | par-dessus l'épaule | vers le haut | par-dessus l'épaule |
    /// | milieu | à gauche | droit devant | à droite |
    /// | bas, 50 % | en bas à gauche | en bas | en bas à droite |
    public func look(at point: CGPoint? = nil) -> PointerLook {
        guard !screen.isEmpty, let target = point ?? last else { return .level }

        let fromTop = (screen.maxY - target.y) / screen.height
        let across = (target.x - screen.minX) / screen.width

        let x: CGFloat = across < Self.sideBand ? -1 : (across > 1 - Self.sideBand ? 1 : 0)

        if fromTop < Self.overShoulderBand {
            // Over the shoulder needs a shoulder to go over: dead centre there
            // is no side to turn to, so the face simply looks up.
            guard x != 0 else { return PointerLook(x: 0, y: -1) }
            // Never quite as far sideways as a straight look, and the head
            // rolls with it — the same proportions `EyeBeat.overLeft` uses, so
            // a pointer glance and a wander glance are the same gesture.
            return PointerLook(x: x * 0.75, y: -0.8, roll: x)
        }
        if fromTop > Self.lowBand {
            return PointerLook(x: x, y: 1)
        }
        return PointerLook(x: x, y: 0)
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

// MARK: - Turning a mood into a face

public extension EyeAnimation {

    /// Lays the pointer's mood over the manifest's own animation.
    ///
    /// An override, not a replacement: the blink, the grain and the beat keep
    /// running underneath, so the face is still the manifest's face. Only where
    /// it looks, how wide it is and how it hops belong to the pointer.
    func following(
        mood: PointerMood, look: PointerLook, eye: FaceFeature, phase: Double
    ) -> EyeAnimation {
        // The same reaches the manifest's own beats use, so a look at the
        // pointer lands exactly where a look at nothing would.
        let reachX = eye.width * EyeSpec.reachX
        let reachY = eye.height * EyeSpec.reachY
        let rollAmount = eye.height * EyeSpec.roll
        var out = self
        switch mood {
        case .resting:
            return self

        case let .startled(progress):
            // Wide, still, and leaning in. A double-take is the absence of a
            // look, not a bigger one — the eyes stop where they are.
            let bump = sin(progress * .pi)          // in and back out
            out.depth = depth * (1 + 0.22 * bump)
            out.squeeze = max(squeeze, 1 + 0.3 * bump)
            out.openness = max(openness, 1)
            out.gaze = CGSize(width: gaze.width * (1 - bump), height: gaze.height * (1 - bump))

        case let .chasing(progress):
            // Like following, but wound up: it is at its reach almost at once
            // and keeps twitching there. It dropped its work for this, so it
            // must not look like it is easing into anything.
            //
            // A steeper curve than following's, which is the whole difference:
            // a higher power rises *sooner*, not later.
            let k = 1 - pow(1 - progress, 5)
            let twitch = 0.09 * sin(phase * 11.7)
            out.gaze = CGSize(
                width: (look.x + twitch) * reachX * k,
                height: look.y * reachY * k)
            out.roll = roll + (look.roll * rollAmount - roll) * k
            out.depth = depth * (1 + 0.12 * k)
            out.squeeze = squeeze * 0.92

        case let .following(progress):
            // Eased in, so the eyes arrive rather than snap to the pointer the
            // instant tracking begins.
            let k = 1 - pow(1 - progress, 3)
            // The cat: a small overshoot that settles, and a tail of interest
            // that never quite sits still.
            let jitter = 0.04 * sin(phase * 7.3)
            out.gaze = CGSize(
                width: (look.x + jitter) * reachX * k,
                height: look.y * reachY * k)
            out.roll = roll + (look.roll * rollAmount - roll) * k
            out.depth = depth * (1 + 0.06 * k)

        case let .amused(progress, _):
            // `^^` and three hops. The shape swap is in `EyePose.following`;
            // here is the bounce and the squint.
            let hop = abs(sin(progress * .pi * 3))
            out.openness = 1
            out.squeeze = 0.75
            out.gaze = CGSize(width: gaze.width, height: -hop * reachY * 0.6)
            out.stretch = stretch * (1 + 0.12 * hop)
        }
        return out
    }
}

public extension EyePose {
    /// The pose a mood needs, if it needs one at all.
    ///
    /// **Laughter, and nothing else.** `^^` is the one place the pointer gets
    /// to change the drawn shape of an eye, because laughing is the one thing
    /// an oval cannot say. Every other mood moves the manifest's own eye and
    /// leaves it the shape its author drew.
    func following(mood: PointerMood) -> EyePose {
        guard case .amused = mood else { return self }
        var out = self
        out.eye.shape = .caret
        out.eye.thickness = max(out.eye.thickness, 0.42)
        return out
    }
}

/// The observable shell the views watch. One instance, owned by the app.
///
/// Holds no clock of its own (decision D3): it is fed by an event monitor when
/// the pointer moves, and read by `BuddyView` on the tick it already runs. A
/// still pointer costs nothing at all.
@MainActor
@Observable
public final class PointerGaze {

    @ObservationIgnored private var state = PointerGazeState()

    /// Bumped on every noted movement so anything observing this object is
    /// invalidated. The state itself is `@ObservationIgnored`: it changes on
    /// every mouse event, and observing it directly would rebuild the view far
    /// more often than the face can be redrawn.
    private(set) public var revision = 0

    /// Where the face is on screen. Set by the panel whenever it moves.
    public var anchor: CGRect {
        get { state.anchor }
        set {
            guard newValue != state.anchor else { return }
            state.anchor = newValue
        }
    }

    /// The display the face sits on, which is what the bands are read off.
    public var screen: CGRect {
        get { state.screen }
        set {
            guard newValue != state.screen else { return }
            state.screen = newValue
        }
    }

    /// Whether an ordinary movement is worth looking at.
    public var followsPointer: Bool {
        get { state.followsPointer }
        set {
            guard newValue != state.followsPointer else { return }
            state.followsPointer = newValue
        }
    }

    /// What a shake earns: a laugh, or a chase.
    public var shakeMeans: ShakeResponse {
        get { state.shakeMeans }
        set {
            guard newValue != state.shakeMeans else { return }
            state.shakeMeans = newValue
        }
    }

    /// Off while the buddy has no business reacting — a face with no clock
    /// cannot animate a look, and one that is busy working should stay working.
    public var isEnabled = true

    public init() {}

    public func note(_ point: CGPoint, at now: Date = Date()) {
        guard isEnabled else { return }
        state.note(point, at: now)
        revision &+= 1
    }

    public func mood(at now: Date = Date()) -> PointerMood {
        guard isEnabled else { return .resting }
        let mood = state.mood(at: now)
        if case .startled = mood { state.markStartled(at: now) }
        return mood
    }

    public func look() -> PointerLook { state.look() }

    /// Poked. Laughs wherever it is and whatever it was doing.
    public func amuse(at now: Date = Date()) {
        guard isEnabled else { return }
        state.amuse(at: now)
        revision &+= 1
    }
}
