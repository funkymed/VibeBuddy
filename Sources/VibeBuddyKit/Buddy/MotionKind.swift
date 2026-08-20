import CoreGraphics
import Foundation

/// The closed vocabulary of buddy movements.
///
/// A manifest **chooses** a motion; it never describes one. That is the line
/// that keeps this safe and cheap:
///
/// - **Safe** — a manifest is a file on disk. Letting it carry a script would
///   put a third-party expression evaluator inside the render loop of an app
///   whose whole premise is zero wakeups at rest.
/// - **Cheap** — the animation budget can be guaranteed for *any* buddy,
///   because every motion here is a pure function of phase, bounded by
///   construction.
///
/// Each case is `phase → transform`, with no state and no clock of its own.
/// Amplitudes stay small deliberately: the notch height is a hard ceiling, and
/// a buddy that overflows it is clipped rather than expressive.
public enum MotionKind: String, Sendable, Equatable, CaseIterable, Decodable {
    /// Perfectly still. Not slow — still. This is what `sleeping` uses, and it
    /// is what lets the whole clock be paused.
    case none
    /// A slow rise and fall, as if breathing.
    case breathe
    /// A quicker, stronger pulse — something is happening.
    case pulse
    /// Small darting shifts, as if glancing around.
    case dart
    /// A short spring, for arrivals.
    case bounce
    /// A brief lateral shudder, for failures.
    case shake

    /// How the buddy is displaced and scaled at a given moment.
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
            // Two frequencies so the movement does not read as a metronome.
            let x = sin(phase * 2 * .pi * 0.9) * 0.6 + sin(phase * 2 * .pi * 1.7) * 0.4
            t.gaze = CGSize(width: x * 4, height: sin(phase * 2 * .pi * 0.4) * 1.5)
            t.scale = 1 + 0.012 * sin(phase * 2 * .pi * 1.3)

        case .bounce:
            // Decaying spring: arrivals should settle, not oscillate forever.
            let decay = exp(-phase * 2.2)
            t.offset = CGSize(width: 0, height: -sin(phase * 2 * .pi * 2.4) * 3 * decay)
            t.scale = 1 + 0.05 * decay * cos(phase * 2 * .pi * 2.4)

        case .shake:
            let decay = exp(-phase * 3.0)
            t.offset = CGSize(width: sin(phase * 2 * .pi * 7) * 2.4 * decay, height: 0)
        }
        return t
    }

    /// Frame rate this motion actually needs.
    ///
    /// A breathing cycle at 0.28 Hz is indistinguishable at 8 fps from 60; a
    /// decaying shake is not. Declaring the need per motion is what lets the
    /// animation budget spend on the ones that show it.
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

    /// How long a transient motion takes to become invisible.
    public var settleDuration: Double { isTransient ? 1.6 : .infinity }
}
