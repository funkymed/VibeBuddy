import CoreGraphics
import Foundation
import Testing
@testable import VibeBuddyKit

@Suite("Following the pointer")
struct PointerGazeTests {
    /// A face 62×30 sitting in the middle of the bar.
    static let anchor = CGRect(x: 800, y: 1130, width: 62, height: 30)
    static let start = Date(timeIntervalSinceReferenceDate: 0)

    /// A 1800×1169 display, the face in its bar.
    static let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)

    static func tracker() -> PointerGazeState {
        var state = PointerGazeState()
        state.anchor = anchor
        state.screen = screen
        return state
    }

    /// A point at a given share across and down the screen.
    static func point(across: CGFloat, down: CGFloat) -> CGPoint {
        CGPoint(x: screen.minX + screen.width * across,
                y: screen.maxY - screen.height * down)
    }

    /// Drags the pointer in a straight line, one sample every `step`.
    @discardableResult
    static func sweep(
        _ state: inout PointerGazeState, from: CGPoint = CGPoint(x: 400, y: 600),
        seconds: TimeInterval, step: TimeInterval = 1.0 / 30, dx: CGFloat = 6
    ) -> Date {
        var now = start
        var point = from
        let end = start.addingTimeInterval(seconds)
        while now <= end {
            state.note(point, at: now)
            point.x += dx
            now = now.addingTimeInterval(step)
        }
        return now
    }

    @Test("a pointer that has only just moved is ignored")
    func nothingHappensImmediately() {
        var state = Self.tracker()
        let now = Self.sweep(&state, seconds: PointerGazeState.noticeDelay - 0.1)
        #expect(state.mood(at: now) == .resting)
    }

    @Test("a deliberate movement is noticed, and the first thing it gets is surprise")
    func startlesBeforeFollowing() {
        var state = Self.tracker()
        let now = Self.sweep(&state, seconds: PointerGazeState.noticeDelay + 0.1)
        guard case let .startled(progress) = state.mood(at: now) else {
            Issue.record("attendu .startled, obtenu \(state.mood(at: now))"); return
        }
        #expect(progress > 0)
        #expect(progress < 1)
    }

    @Test("surprise gives way to tracking")
    func followsAfterTheDoubleTake() {
        var state = Self.tracker()
        let after = PointerGazeState.noticeDelay + PointerGazeState.startleDuration + 0.2
        let now = Self.sweep(&state, seconds: after)
        guard case .following = state.mood(at: now) else {
            Issue.record("attendu .following, obtenu \(state.mood(at: now))"); return
        }
    }

    @Test("the eyes arrive rather than snap")
    func trackingEasesIn() {
        // Sampled a clear step inside the tracking window at each end, not on its edge:
        // at the boundary the double-take is still on screen, one float epsilon short
        // of finishing.
        let base = PointerGazeState.noticeDelay + PointerGazeState.startleDuration
        var early: Double = 1, late: Double = 0
        var s1 = Self.tracker(), s2 = Self.tracker()
        let t1 = Self.sweep(&s1, seconds: base + 0.06)
        let t2 = Self.sweep(&s2, seconds: base + PointerGazeState.catchUp + 0.06)
        if case let .following(p) = s1.mood(at: t1) { early = p }
        if case let .following(p) = s2.mood(at: t2) { late = p }
        #expect(early < late)
        #expect(late == 1)
    }

    @Test("a pointer left alone hands the face back to its own cycle")
    func restsWhenTheMouseStops() {
        var state = Self.tracker()
        let moved = Self.sweep(&state, seconds: 1.2)
        let later = moved.addingTimeInterval(PointerGazeState.restDelay + 0.2)
        #expect(state.mood(at: later) == .resting)
    }

    @Test("a hand resting on the trackpad is not a movement")
    func ignoresJitter() {
        var state = Self.tracker()
        var now = Self.start
        // Sub-threshold wobble, for well past the notice delay.
        for i in 0..<60 {
            state.note(CGPoint(x: 400 + CGFloat(i % 2), y: 600), at: now)
            now = now.addingTimeInterval(1.0 / 30)
        }
        #expect(state.mood(at: now) == .resting)
    }

    /// Shakes the pointer `turns` times, each leg `swing` points wide.
    @discardableResult
    static func shake(
        _ state: inout PointerGazeState, turns: Int, swing: CGFloat,
        step: TimeInterval = 0.04
    ) -> Date {
        var now = start
        var x: CGFloat = 900
        for i in 0...turns {
            x += (i % 2 == 0) ? swing : -swing
            state.note(CGPoint(x: x, y: 600), at: now)
            now = now.addingTimeInterval(step)
        }
        return now
    }

    // One gesture, one meaning, whatever the face was doing: a shake starts a chase.
    @Test("shaking the mouse starts a chase, from any face")
    func wiggleChases() {
        var state = Self.tracker()
        let now = Self.shake(&state, turns: 7, swing: 60)
        #expect(state.isChasing)
        guard case .chasing = state.mood(at: now) else {
            Issue.record("attendu .chasing, obtenu \(state.mood(at: now))"); return
        }
    }

    @Test("shaking again, mid-chase, is the joke")
    func secondShakeLaughs() {
        var state = Self.tracker()
        var now = Self.shake(&state, turns: 7, swing: 60)
        // A second gesture, not the tail of the first: past `wiggleCooldown`, and still
        // inside `restDelay` so the chase it lands on is the same one.
        now = now.addingTimeInterval(0.8)
        var x: CGFloat = 900
        for i in 0..<9 {
            x += (i % 2 == 0) ? 60 : -60
            state.note(CGPoint(x: x, y: 600), at: now)
            now = now.addingTimeInterval(0.04)
        }
        guard case .amused = state.mood(at: now) else {
            Issue.record("attendu .amused, obtenu \(state.mood(at: now))"); return
        }
    }

    // The whole point of the tightening: aiming at a button and overshooting it makes
    // two or three small reversals, and it used to be enough.
    @Test("aiming and correcting is not a shake")
    func correctingIsNotAShake() {
        var state = Self.tracker()
        // Wide enough legs, but only three turns.
        _ = Self.shake(&state, turns: 3, swing: 60)
        #expect(!state.isChasing, "trois virages ont suffi")

        // Plenty of turns, but each one a wobble rather than a swing.
        var wobbly = Self.tracker()
        _ = Self.shake(&wobbly, turns: 11, swing: 8)
        #expect(!wobbly.isChasing, "des tremblements ont suffi")
    }

    @Test("a shake spread out over time is not a shake either")
    func slowShakeIsNotAShake() {
        var state = Self.tracker()
        // Wide legs, enough of them, but one every half-second: three of them no longer
        // fit inside `wiggleWindow`, which is what tells a shake from a sweep.
        _ = Self.shake(&state, turns: 9, swing: 60, step: 0.5)
        #expect(!state.isChasing, "une secousse lente a suffi")
    }

    @Test("the fit passes")
    func amusementEnds() {
        var state = Self.tracker()
        let now = Self.start
        state.amuse(at: now)
        let after = now.addingTimeInterval(
            PointerGazeState.amusementDuration + PointerGazeState.restDelay + 0.1)
        #expect(state.mood(at: after) == .resting)
    }

    // `^^` is for laughing and for nothing else: every other mood leaves the eye the
    // shape its manifest drew.
    @Test("only laughter changes the drawn shape")
    func onlyLaughterChangesTheShape() {
        let pose = EyePose(eye: FaceFeature(shape: .oval))
        #expect(pose.following(mood: .amused(progress: 0.5, chasing: false)).eye.shape == .caret)
        #expect(pose.following(mood: .following(progress: 1)).eye.shape == .oval)
        #expect(pose.following(mood: .startled(progress: 0.5)).eye.shape == .oval)
        #expect(pose.following(mood: .resting) == pose)
    }

    @Test("the middle band looks level, and to the side the pointer is on")
    func middleBandIsLevel() {
        var state = Self.tracker()
        for (across, expected) in [(0.1, -1.0), (0.5, 0.0), (0.9, 1.0)] {
            state.note(Self.point(across: across, down: 0.4), at: Self.start)
            let look = state.look()
            #expect(look.y == 0)
            #expect(look.x == CGFloat(expected))
            #expect(look.roll == 0)
        }
    }

    @Test("below the middle of the screen the eyes go down")
    func lowerHalfLooksDown() {
        var state = Self.tracker()
        for across in [0.1, 0.5, 0.9] {
            state.note(Self.point(across: across, down: 0.75), at: Self.start)
            #expect(state.look().y == 1)
        }
        // And keeps the side it is on.
        state.note(Self.point(across: 0.05, down: 0.9), at: Self.start)
        #expect(state.look().x == -1)
    }

    @Test("the top quarter is a glance over the shoulder, head rolled with it")
    func topQuarterLooksOverTheShoulder() {
        var state = Self.tracker()
        state.note(Self.point(across: 0.9, down: 0.1), at: Self.start)
        let right = state.look()
        #expect(right.y < 0)
        #expect(right.x > 0)
        #expect(right.roll == 1)
        // Never as far sideways as a straight look: that is what makes it read as a
        // turn of the head rather than a look.
        #expect(right.x < 1)

        state.note(Self.point(across: 0.05, down: 0.1), at: Self.start)
        #expect(state.look().roll == -1)
    }

    // No shoulder to look over when the pointer is straight above.
    @Test("dead centre and high, it simply looks up")
    func topCentreLooksUp() {
        var state = Self.tracker()
        state.note(Self.point(across: 0.5, down: 0.1), at: Self.start)
        let look = state.look()
        #expect(look.y == -1)
        #expect(look.x == 0)
        #expect(look.roll == 0)
    }

    @Test("the bands sit exactly where they are named")
    func bandEdges() {
        var state = Self.tracker()
        // Just inside the top quarter, then just below it.
        state.note(Self.point(across: 0.9, down: PointerGazeState.overShoulderBand - 0.01),
                   at: Self.start)
        #expect(state.look().roll != 0)
        state.note(Self.point(across: 0.9, down: PointerGazeState.overShoulderBand + 0.01),
                   at: Self.start)
        #expect(state.look().roll == 0)
        #expect(state.look().y == 0)
        // Just past the middle.
        state.note(Self.point(across: 0.9, down: PointerGazeState.lowBand + 0.01), at: Self.start)
        #expect(state.look().y == 1)
    }

    @Test("with no display to divide, the face stays level")
    func noScreenNoLook() {
        var state = PointerGazeState()
        state.anchor = Self.anchor
        state.note(Self.point(across: 0.9, down: 0.9), at: Self.start)
        #expect(state.look() == .level)
    }

    @Test("with nowhere to be drawn, nothing happens at all")
    func noAnchorNoMood() {
        var state = PointerGazeState()          // anchor left empty
        let now = Self.sweep(&state, seconds: 2)
        #expect(state.mood(at: now) == .resting)
    }

    @Test("resting leaves the manifest's animation untouched")
    func restingIsATrueNoOp() {
        let base = EyeAnimation.at(phase: 1.3, spec: EyeSpec(pose: EyePose()))
        #expect(base.following(mood: .resting, look: PointerLook(x: 1, y: 1),
                               eye: FaceFeature(), phase: 1.3) == base)
    }

    @Test("tracking sends the gaze to the zone's own reach")
    func followingMovesTheGaze() {
        let eye = FaceFeature()
        let base = EyeAnimation.at(phase: 1.3, spec: EyeSpec(pose: EyePose(eye: eye)))
        let out = base.following(
            mood: .following(progress: 1), look: PointerLook(x: 1, y: 0),
            eye: eye, phase: 0)
        // The same reach the manifest's own `right` beat uses, give or take the cat's
        // small jitter.
        let reach = eye.width * EyeSpec.reachX
        #expect(out.gaze.width > 0)
        #expect(abs(out.gaze.width - reach) <= reach * 0.06)
    }

    @Test("an over-the-shoulder look rolls the head")
    func followingRolls() {
        let eye = FaceFeature()
        let base = EyeAnimation.at(phase: 0.2, spec: EyeSpec(pose: EyePose(eye: eye)))
        let out = base.following(
            mood: .following(progress: 1), look: PointerLook(x: 0.75, y: -0.8, roll: 1),
            eye: eye, phase: 0.2)
        #expect(out.roll > 0)
        #expect(out.gaze.height < 0)
    }

    @Test("surprise widens the face and stops the look where it stands")
    func startleWidens() {
        let base = EyeAnimation.at(phase: 0.9, spec: EyeSpec(pose: EyePose()))
        let out = base.following(
            mood: .startled(progress: 0.5), look: PointerLook(x: 1, y: 0),
            eye: FaceFeature(), phase: 0.9)
        #expect(out.depth > base.depth)
        #expect(abs(out.gaze.width) <= abs(base.gaze.width) + 0.001)
    }

    @Test("laughing squints and hops")
    func amusementHops() {
        let base = EyeAnimation.at(phase: 0.4, spec: EyeSpec(pose: EyePose()))
        let mid = base.following(mood: .amused(progress: 1.0 / 6, chasing: false), look: .level,
                                 eye: FaceFeature(), phase: 0.4)
        #expect(mid.squeeze < base.squeeze)
        #expect(mid.gaze.height < 0)           // up, on the hop
    }
}

/// The clock the mood needs, read without advancing anything: `sleeping` renders at
/// 0 Hz because its spec cannot move, and a paused timeline froze the chase at
/// progress zero — eyes borrowed, no pink, no pursuit.
@Suite("The mood keeps the clock alive")
struct MoodClockTests {
    @Test("a chase needs frames while the pointer moves, and through the fade")
    func chaseAnimates() {
        var state = PointerGazeTests.tracker()
        state.followsPointer = false     // sleeping
        let now = PointerGazeTests.shake(&state, turns: 7, swing: 60)
        #expect(state.isAnimating(at: now))
        // Through the fade…
        let fading = now.addingTimeInterval(
            PointerGazeState.restDelay + PointerGazeState.chaseFade - 0.1)
        #expect(state.isAnimating(at: fading))
        // …and not a moment past it: `chasingSince` survives the quiet, the clock must
        // not.
        let after = now.addingTimeInterval(
            PointerGazeState.restDelay + PointerGazeState.chaseFade + 0.1)
        #expect(state.isChasing)
        #expect(!state.isAnimating(at: after))
    }

    @Test("a laugh needs frames until it is over")
    func laughAnimates() {
        var state = PointerGazeTests.tracker()
        state.followsPointer = false
        let now = Date(timeIntervalSince1970: 1_000_000)
        state.amuse(at: now)
        #expect(state.isAnimating(at: now.addingTimeInterval(0.5)))
        #expect(!state.isAnimating(at: now.addingTimeInterval(
            PointerGazeState.amusementDuration + 0.1)))
    }

    @Test("a sleeping face with a quiet pointer asks for nothing")
    func quietIsStill() {
        var state = PointerGazeTests.tracker()
        state.followsPointer = false
        let now = Date(timeIntervalSince1970: 1_000_000)
        state.note(CGPoint(x: 900, y: 600), at: now)
        state.note(CGPoint(x: 960, y: 600), at: now.addingTimeInterval(0.04))
        // One straight movement: no chase, and a face that does not follow has no
        // business waking for it.
        #expect(!state.isAnimating(at: now.addingTimeInterval(0.1)))
    }
}

/// Shaking the mouse at a buddy that is working drops it into a chase.
@Suite("The chase")
struct PointerChaseTests {
    /// What the panel sets while the buddy is working: it does not look up at passing
    /// movement, but a shake still reaches it.
    static func busy() -> PointerGazeState {
        var state = PointerGazeState()
        state.anchor = PointerGazeTests.anchor
        state.screen = PointerGazeTests.screen
        state.followsPointer = false
        return state
    }

    @Test("a working buddy ignores the pointer going past")
    func busyIgnoresOrdinaryMovement() {
        var state = Self.busy()
        let now = PointerGazeTests.sweep(&state, seconds: 3)
        #expect(state.mood(at: now) == .resting)
    }

    @Test("shaking it gets it to drop everything and chase")
    func shakeStartsTheChase() {
        var state = Self.busy()
        let now = PointerGazeTests.shake(&state, turns: 7, swing: 60)
        guard case .chasing = state.mood(at: now) else {
            Issue.record("attendu .chasing, obtenu \(state.mood(at: now))"); return
        }
    }

    @Test("a first shake is a chase, never a joke")
    func shakeDoesNotAmuseWhileBusy() {
        var state = Self.busy()
        let now = PointerGazeTests.shake(&state, turns: 7, swing: 60)
        if case .amused = state.mood(at: now) { Issue.record("il a ri au lieu de chasser") }
    }

    // The point of the change: `finished` chases too, and so does every other face that
    // carries a clock.
    @Test("a buddy that has finished chases just the same")
    func finishedChasesToo() {
        var state = PointerGazeTests.tracker()   // follows the pointer, like idle and finished
        let now = PointerGazeTests.shake(&state, turns: 7, swing: 60)
        guard case .chasing = state.mood(at: now) else {
            Issue.record("attendu .chasing, obtenu \(state.mood(at: now))"); return
        }
    }

    @Test("the chase lasts as long as the pointer keeps moving, and not a moment longer")
    func chaseEndsWithTheMovement() {
        var state = Self.busy()
        var now = PointerGazeTests.shake(&state, turns: 7, swing: 60)

        // Still moving, in a straight line now: still chasing.
        var x: CGFloat = 900
        for _ in 0..<20 {
            x += 12
            state.note(CGPoint(x: x, y: 600), at: now)
            now = now.addingTimeInterval(1.0 / 30)
        }
        guard case .chasing = state.mood(at: now) else {
            Issue.record("la chasse s'est arrêtée alors que la souris bougeait"); return
        }

        // Hands off.
        let after = now.addingTimeInterval(
            PointerGazeState.restDelay + PointerGazeState.chaseFade + 0.1)
        #expect(state.mood(at: after) == .resting)
    }

    @Test("the chase lets go of the pointer over a fade, not in a cut")
    func chaseFadesOut() {
        var state = Self.busy()
        var now = PointerGazeTests.shake(&state, turns: 7, swing: 60)
        // Full strength while the pointer is still moving.
        var x: CGFloat = 900
        for _ in 0..<20 {
            x += 12
            state.note(CGPoint(x: x, y: 600), at: now)
            now = now.addingTimeInterval(1.0 / 30)
        }
        #expect(state.mood(at: now).tintStrength == 1)

        // Hands off: the colour and the look ease back together.
        let midFade = now.addingTimeInterval(
            PointerGazeState.restDelay + PointerGazeState.chaseFade / 2)
        let strength = state.mood(at: midFade).tintStrength
        #expect(strength > 0)
        #expect(strength < 1)

        // And it is gone once the fade is over.
        let after = now.addingTimeInterval(
            PointerGazeState.restDelay + PointerGazeState.chaseFade + 0.05)
        #expect(state.mood(at: after) == .resting)
    }

    @Test("the chase wears the colour that says it stopped working")
    func chaseIsPink() {
        #expect(PointerMood.chasing(progress: 0.5).tint == "#FF5FA2")
        #expect(PointerMood.chasing(progress: 0.5).tintStrength == 0.5)
        #expect(PointerMood.resting.tintStrength == 0)
        // And nothing else overrides the manifest's colour.
        #expect(PointerMood.resting.tint == nil)
        #expect(PointerMood.following(progress: 1).tint == nil)
        #expect(PointerMood.amused(progress: 0.5, chasing: false).tint == nil)
        #expect(PointerMood.startled(progress: 0.5).tint == nil)
    }

    // A narrowed working eye chasing a mouse reads as annoyance; the wide round one
    // reads as play.
    @Test("the chase borrows the eyes of a buddy that has finished")
    func chaseBorrowsFinishedEyes() {
        #expect(PointerMood.chasing(progress: 1).borrowedExpression == .finished)
        #expect(PointerMood.resting.borrowedExpression == nil)
        #expect(PointerMood.amused(progress: 1, chasing: false).borrowedExpression == nil)
        #expect(PointerMood.following(progress: 1).borrowedExpression == nil)
    }

    @Test("chasing goes further, faster than merely following")
    func chaseIsKeener() {
        let eye = FaceFeature()
        let base = EyeAnimation.at(phase: 0.5, spec: EyeSpec(pose: EyePose(eye: eye)))
        let look = PointerLook(x: 1, y: 0)
        let early = 0.3
        let chasing = base.following(mood: .chasing(progress: early), look: look,
                                     eye: eye, phase: 0.5)
        let following = base.following(mood: .following(progress: early), look: look,
                                       eye: eye, phase: 0.5)
        #expect(chasing.gaze.width > following.gaze.width)
        #expect(chasing.depth > following.depth)
    }
}

/// Poking the face.
@Suite("Being poked")
struct PointerPokeTests {
    @Test("a poke makes it laugh, with none of the evidence a shake needs")
    func pokeAmuses() {
        var state = PointerGazeTests.tracker()
        let now = PointerGazeTests.start
        state.amuse(at: now)
        guard case .amused = state.mood(at: now) else {
            Issue.record("attendu .amused, obtenu \(state.mood(at: now))"); return
        }
    }

    @Test("the laugh outranks a chase, and the chase picks up after it")
    func pokeInterruptsTheChase() {
        var state = PointerChaseTests.busy()
        var now = PointerGazeTests.shake(&state, turns: 7, swing: 60)
        guard case .chasing = state.mood(at: now) else {
            Issue.record("la chasse n'a pas démarré"); return
        }

        state.amuse(at: now)
        guard case .amused = state.mood(at: now) else {
            Issue.record("le clic n'a pas été entendu"); return
        }

        // Still chasing once the laugh is over, provided the pointer is still moving:
        // the poke suspended it, it did not cancel it.
        var x: CGFloat = 900
        let end = now.addingTimeInterval(PointerGazeState.amusementDuration + 0.05)
        while now < end {
            x += 12
            state.note(CGPoint(x: x, y: 600), at: now)
            now = now.addingTimeInterval(1.0 / 30)
        }
        guard case .chasing = state.mood(at: now) else {
            Issue.record("la chasse ne reprend pas, obtenu \(state.mood(at: now))"); return
        }
    }

    @Test("a poke on a working buddy laughs rather than chases")
    func pokeIsNeverAChase() {
        var state = PointerChaseTests.busy()
        state.amuse(at: PointerGazeTests.start)
        if case .chasing = state.mood(at: PointerGazeTests.start) {
            Issue.record("le clic a lancé une chasse")
        }
    }

    @Test("the laugh runs out")
    func pokeWearsOff() {
        var state = PointerGazeTests.tracker()
        let now = PointerGazeTests.start
        state.amuse(at: now)
        let after = now.addingTimeInterval(PointerGazeState.amusementDuration + 0.01)
        #expect(state.mood(at: after) == .resting)
    }
}

/// Laughing is one behaviour with several ways in, and it must stay one.
@Suite("Laughing, from anywhere")
struct LaughterEntryPointsTests {
    /// The ways a laugh starts, each producing the same mood.
    @Test("a click at rest, a click while busy, and a shake mid-chase all laugh")
    func everyRouteLaughs() {
        // 1 — clicking on an idle buddy.
        var idle = PointerGazeTests.tracker()
        idle.amuse(at: PointerGazeTests.start)
        guard case .amused = idle.mood(at: PointerGazeTests.start) else {
            Issue.record("le clic au repos n'a pas fait rire"); return
        }

        // 2 — clicking on one that is busy.
        var poked = PointerChaseTests.busy()
        poked.amuse(at: PointerGazeTests.start)
        guard case .amused = poked.mood(at: PointerGazeTests.start) else {
            Issue.record("le clic n'a pas fait rire"); return
        }

        // 3 — shaking at one already chasing.
        var chasing = PointerChaseTests.busy()
        var now = PointerGazeTests.shake(&chasing, turns: 7, swing: 60)
        #expect(chasing.isChasing)
        now = now.addingTimeInterval(0.05)
        var again = chasing
        _ = PointerGazeTests.shake(&again, turns: 7, swing: 60)
        // The second shake, replayed on the same state, lands as a laugh because the
        // chase is already on.
        now = now.addingTimeInterval(0.8)
        var x: CGFloat = 900
        for i in 0..<9 {
            x += (i % 2 == 0) ? 60 : -60
            chasing.note(CGPoint(x: x, y: 600), at: now)
            now = now.addingTimeInterval(0.04)
        }
        guard case .amused = chasing.mood(at: now) else {
            Issue.record("la secousse en pleine chasse n'a pas fait rire, obtenu \(chasing.mood(at: now))")
            return
        }
    }

    // The laugh happens *inside* the chase: the buddy has not let go, so it must not
    // let go of the colour either.
    @Test("a laugh during a chase keeps the chase's colour, and its eyes after")
    func laughingMidChaseStaysPink() {
        var state = PointerChaseTests.busy()
        var now = PointerGazeTests.shake(&state, turns: 7, swing: 60)
        state.amuse(at: now)

        let mood = state.mood(at: now)
        guard case .amused(_, let chasing) = mood else {
            Issue.record("attendu .amused, obtenu \(mood)"); return
        }
        #expect(chasing)
        #expect(mood.tint == "#FF5FA2")
        #expect(mood.tintStrength == 1)
        #expect(mood.borrowedExpression == .finished)

        // And once the joke is over, the chase is still on.
        var x: CGFloat = 900
        let end = now.addingTimeInterval(PointerGazeState.amusementDuration + 0.05)
        while now < end {
            x += 12
            state.note(CGPoint(x: x, y: 600), at: now)
            now = now.addingTimeInterval(1.0 / 30)
        }
        guard case .chasing = state.mood(at: now) else {
            Issue.record("la chasse n'a pas repris, obtenu \(state.mood(at: now))"); return
        }
    }

    @Test("a laugh with no chase behind it wears the manifest's own colour")
    func laughingAloneIsNotPink() {
        var state = PointerGazeTests.tracker()
        state.amuse(at: PointerGazeTests.start)
        let mood = state.mood(at: PointerGazeTests.start)
        #expect(mood.tint == nil)
        #expect(mood.tintStrength == 0)
        #expect(mood.borrowedExpression == nil)
    }
}
