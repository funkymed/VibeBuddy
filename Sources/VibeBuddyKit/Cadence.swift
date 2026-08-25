import Foundation

/// How often a subsystem wants to be woken.
public enum Cadence: Sendable, Equatable, CaseIterable {
    case off
    case lazy
    case idle
    case active

    /// The finest cadence is 1 Hz, so the resting budget of 2 wakeups/s holds by
    /// construction.
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
