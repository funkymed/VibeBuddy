import Foundation

/// The panel's state, its re-entry guard and its frame generation counter,
/// with no window attached.
///
/// Extracted from `NotchPanel` so the two things that only ever went wrong at
/// runtime — the deferred replay and the generation stamp — can be exercised
/// without a screen. It holds no AppKit: the effects of a state change are the
/// caller's business, delivered through `onApply`.
@MainActor
public final class PanelStateMachine {

    /// One application of the state: what to draw, whether to animate it, and
    /// the stamp an animation completion is checked against.
    public struct Pass: Sendable, Equatable {
        public let state: PanelState
        public let animated: Bool
        public let generation: Int

        public init(state: PanelState, animated: Bool, generation: Int) {
            self.state = state
            self.animated = animated
            self.generation = generation
        }
    }

    /// See the note on the bound inside `apply(animated:)`.
    public static let maxReapplyDepth = 10

    public private(set) var state: PanelState = .hidden
    public private(set) var frameGeneration = 0

    /// Called once per pass, on the state as it stands at that moment.
    public var onApply: ((Pass) -> Void)?

    /// Guards against `apply` being re-entered while it runs.
    ///
    /// It sets `host.hitRegion`, which rebuilds the tracking area, which can
    /// report hover, which changes `state`, whose `didSet` calls back in here.
    /// The inner call is deferred rather than run: the outer one has already
    /// computed a size and a target for the state it was leaving, and letting
    /// the two interleave is what left the panel stuck black. Once the outer
    /// call finishes, the deferred one runs against whatever the state is by
    /// then, so it converges.
    private var applying = false
    private var needsReapply = false
    private var reapplyDepth = 0

    public init() {}

    /// Mirrors the old `didSet`: only a real change applies.
    public func move(to next: PanelState) {
        guard next != state else { return }
        state = next
        apply(animated: true)
    }

    public func apply(animated: Bool = true) {
        if applying { needsReapply = true; return }
        applying = true
        defer {
            applying = false
            if needsReapply {
                needsReapply = false
                // **Bounded.** The deferred replay converges because the state
                // settles, but « converges » was an assumption, and an
                // assumption that is wrong here does not misdraw — it hangs the
                // main thread with a beachball, which is what happened. Ten is
                // far more than any real transition needs; reaching it means
                // something is oscillating, and stopping leaves the panel in a
                // state `finishStateChange` will correct.
                reapplyDepth += 1
                if reapplyDepth < Self.maxReapplyDepth {
                    apply(animated: animated)
                }
            }
            if !applying { reapplyDepth = 0 }
        }

        frameGeneration += 1
        onApply?(Pass(state: state, animated: animated, generation: frameGeneration))
    }

    /// Stamps a frame change driven by something other than a state change —
    /// `resizeToContent` — from the same counter, so the later of the two
    /// animations always wins.
    public func nextGeneration() -> Int {
        frameGeneration += 1
        return frameGeneration
    }

    /// A superseded animation's completion describes a frame already left.
    /// `nil` means « never stale »: it is the default for callers that drive no
    /// animation of their own.
    public func isCurrent(_ generation: Int?) -> Bool {
        guard let generation else { return true }
        return generation == frameGeneration
    }

    /// Both hover sources arbitrate here, and nowhere else.
    ///
    /// Returns the state to move to, or `nil` when the hover changes nothing.
    /// `opening` and `holdingAnAsk` are the two reasons a panel refuses to
    /// close under a pointer that left it.
    public static func nextState(
        from state: PanelState, hovering: Bool, opening: Bool, holdingAnAsk: Bool
    ) -> PanelState? {
        if hovering, state == .pill { return .panel }
        if !hovering, state == .panel, !opening, !holdingAnAsk { return .pill }
        return nil
    }
}
