import Foundation
import Observation

/// Global ceiling on animation cost, consulted by every view that draws motion.
///
/// # Why this exists
///
/// The reference implementation spends its animation budget invisibly:
/// eighteen `withAnimation(...).repeatForever` calls across `BuddyFace.swift`,
/// each installing an implicit `CADisplayLink` that is never torn down — not
/// when the view scrolls off screen, not when the window hides. `withAnimation`
/// reads as free at the call site, which is exactly why it accumulates.
///
/// Here motion has one dial, and it is observable. A view that wants to animate
/// asks what it is allowed to spend; when the answer is `0` it draws a static
/// frame and installs no clock at all.
@MainActor
@Observable
public final class AnimationBudget {

    /// Frames per second the UI may draw at. `0` means static — not slow.
    public enum Tier: Double, Sendable, CaseIterable {
        /// Nothing visible, or the machine is asleep. No clock, no redraw.
        case still = 0
        /// Visible but nothing happening. Enough for a blink, cheap enough to
        /// leave running.
        case ambient = 8
        /// Something is actively happening and the motion carries meaning.
        case lively = 30
    }

    public private(set) var tier: Tier = .still

    /// Convenience for `TimelineView(.animation(minimumInterval:paused:))`.
    public var frameRate: Double { tier.rawValue }

    /// `TimelineView` wants an interval, and must be paused rather than given
    /// an infinite one.
    public var minimumInterval: Double { tier == .still ? 1 : 1 / tier.rawValue }
    public var isPaused: Bool { tier == .still }

    /// Implicit SwiftUI animations are forbidden below `.lively`: they outlive
    /// the state change that triggered them and cannot be interrogated or
    /// stopped once installed.
    public var allowsImplicitAnimations: Bool { tier == .lively }

    public init() {}

    public func set(_ tier: Tier) {
        guard tier != self.tier else { return }
        self.tier = tier
    }

    /// Resolve the tier from the two facts that actually govern it.
    ///
    /// Hidden always wins. A pill that is not on screen costs nothing, whatever
    /// Claude happens to be doing.
    public func update(isVisible: Bool, isBusy: Bool) {
        set(!isVisible ? .still : (isBusy ? .lively : .ambient))
    }
}
