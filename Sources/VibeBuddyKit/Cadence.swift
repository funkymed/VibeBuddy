import Foundation

/// How often a subsystem wants to be woken.
///
/// Deliberately a closed set of four. Arbitrary intervals are how an app ends
/// up with seven uncoordinated timers — the state the reference implementation
/// is in. If a subsystem needs something outside this set, that is a design
/// conversation, not a parameter.
public enum Cadence: Sendable, Equatable, CaseIterable {
    /// Never woken. The default, and the state everything returns to on sleep.
    case off
    /// 30 s — background liveness checks while nothing is happening.
    case lazy
    /// 5 s — something is on screen but idle.
    case idle
    /// 1 s — a session is actively doing work.
    case active

    /// Every cadence is a resting cadence: the finest is 1 Hz, so the resting
    /// budget of two wakeups per second holds by construction. Hover, which once
    /// wanted 10 Hz, is event-driven now — see `ClickThroughHostView`.
    public static var resting: [Cadence] { allCases }

    public var interval: TimeInterval? {
        switch self {
        case .off:    return nil
        case .lazy:   return 30
        case .idle:   return 5
        case .active: return 1
        }
    }
}
