import CoreGraphics
import Foundation

/// The closed vocabulary of buddy movements: a manifest chooses one, it never
/// describes one. Each case is `phase → transform`, stateless and bounded.
/// See RFC-005, "Notes d'implémentation".
public enum MotionKind: String, Sendable, Equatable, CaseIterable, Decodable {
    /// Perfectly still — not slow. This is what lets the whole clock be paused.
    case none
    case breathe
    case pulse
    case dart
    case bounce
    case shake

    public struct Transform: Sendable, Equatable {
        public var scale: CGFloat = 1
        public var offset: CGSize = .zero
        /// Extra gaze displacement, applied to the eyes only.
        public var gaze: CGSize = .zero
    }

    /// - Parameter phase: seconds since the animation started.
    public func transform(at phase: Double) -> Transform {
        var t = Transform()
        switch self {
        case .none:
            return t

        case .breathe:
            // 0.28 Hz: slow enough to read as breathing rather than throbbing.
            t.scale = 1 + 0.020 * sin(phase * 2 * .pi * 0.28)

        case .pulse:
            t.scale = 1 + 0.045 * sin(phase * 2 * .pi * 1.1)

        case .dart:
            let x = sin(phase * 2 * .pi * 0.9) * 0.6 + sin(phase * 2 * .pi * 1.7) * 0.4
            t.gaze = CGSize(width: x * 4, height: sin(phase * 2 * .pi * 0.4) * 1.5)
            t.scale = 1 + 0.012 * sin(phase * 2 * .pi * 1.3)

        case .bounce:
            let decay = exp(-phase * 2.2)
            t.offset = CGSize(width: 0, height: -sin(phase * 2 * .pi * 2.4) * 3 * decay)
            t.scale = 1 + 0.05 * decay * cos(phase * 2 * .pi * 2.4)

        case .shake:
            let decay = exp(-phase * 3.0)
            t.offset = CGSize(width: sin(phase * 2 * .pi * 7) * 2.4 * decay, height: 0)
        }
        return t
    }

    /// Frame rate this motion actually needs: a 0.28 Hz breathing cycle is
    /// indistinguishable at 8 fps from 60, a decaying shake is not.
    public var preferredTier: AnimationBudget.Tier {
        switch self {
        case .none:                     return .still
        case .breathe:                  return .ambient
        case .pulse, .dart:             return .ambient
        case .bounce, .shake:           return .lively
        }
    }

    /// Whether the motion settles on its own, so the clock can stop afterwards.
    public var isTransient: Bool { self == .bounce || self == .shake }

    public var settleDuration: Double { isTransient ? 1.6 : .infinity }
}
