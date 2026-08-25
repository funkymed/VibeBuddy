import Foundation

/// The panel's state, its re-entry guard and its frame generation counter, with no
/// window attached.
@MainActor
public final class PanelStateMachine {
    /// One application of the state: what to draw, whether to animate it, and the stamp
    /// an animation completion is checked against.
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
                // Bounded. The deferred replay converges because the state settles,
                // but « converges » was an assumption, and an assumption that is wrong
                // here does not misdraw — it hangs the main thread with a beachball,
                // which is what happened.
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
    /// `resizeToContent` — from the same counter, so the later of the two animations
    /// always wins.
    public func nextGeneration() -> Int {
        frameGeneration += 1
        return frameGeneration
    }

    /// A superseded animation's completion describes a frame already left.
    public func isCurrent(_ generation: Int?) -> Bool {
        guard let generation else { return true }
        return generation == frameGeneration
    }

    /// Both hover sources arbitrate here, and nowhere else.
    public static func nextState(
        from state: PanelState, hovering: Bool, opening: Bool, holdingAnAsk: Bool
    ) -> PanelState? {
        if hovering, state == .pill { return .panel }
        if !hovering, state == .panel, !opening, !holdingAnAsk { return .pill }
        return nil
    }
}
