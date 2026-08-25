import Foundation
import Observation

/// Global ceiling on animation cost, consulted by every view that draws motion.
@MainActor
@Observable
public final class AnimationBudget {
    /// Frames per second the UI may draw at.
    public enum Tier: Double, Sendable, CaseIterable {
        case still = 0
        case ambient = 8
        case lively = 30
    }

    public private(set) var tier: Tier = .still

    public var frameRate: Double { tier.rawValue }

    /// `TimelineView` must be paused, not handed an infinite interval.
    public var minimumInterval: Double { tier == .still ? 1 : 1 / tier.rawValue }
    public var isPaused: Bool { tier == .still }

    /// Do not use implicit SwiftUI animations below `.lively`: they outlive the state
    /// change that triggered them and cannot be stopped once installed.
    public var allowsImplicitAnimations: Bool { tier == .lively }

    public init() {}

    public func set(_ tier: Tier) {
        guard tier != self.tier else { return }
        self.tier = tier
    }

    public func update(isVisible: Bool, isBusy: Bool) {
        set(!isVisible ? .still : (isBusy ? .lively : .ambient))
    }
}
