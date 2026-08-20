import Foundation

/// Decides whether an alert actually reaches the user.
///
/// The state machine decides *what happened*; this decides *whether to say so*.
/// Keeping them apart matters because the reasons to stay quiet have nothing to
/// do with the reasons a turn ended.
///
/// Pure by construction — every decision takes the current time as an argument
/// rather than reading a clock — so the suppression rules can be tested without
/// waiting for wall time to pass.
public struct AlertPolicy: Sendable {

    /// Minimum gap between two visual alerts, whatever their source.
    ///
    /// Three sessions finishing at once should produce one interruption and then
    /// a pause, not three overlapping pop-outs. Twelve seconds is the value the
    /// reference implementation settled on for its speech controller, and there
    /// is no reason to relitigate it.
    public static let minimumGap: TimeInterval = 12

    /// Window in which the same session repeating the same alert is treated as
    /// one event. Guards against a transcript being rewritten — on compaction,
    /// for instance — and replaying a completion.
    public static let dedupeWindow: TimeInterval = 60

    public struct Decision: Sendable, Equatable {
        public let allowed: Bool
        public let reason: String
    }

    private var lastDelivery: Date?
    private var recent: [String: Date] = [:]

    public init() {}

    /// Should this alert be shown?
    ///
    /// - Parameter hostingTerminalIsFrontmost: whether the user is already
    ///   looking at the terminal this alert is about. If they are, the alert is
    ///   noise — they can see it happen.
    public mutating func admit(
        _ alert: SessionAlert,
        now: Date,
        hostingTerminalIsFrontmost: Bool
    ) -> Decision {
        // Looking at it already. This is the suppression that matters most:
        // notifying someone about the window they are staring at is the fastest
        // way to teach them to ignore notifications.
        if hostingTerminalIsFrontmost {
            return Decision(allowed: false, reason: "terminal au premier plan")
        }

        let key = "\(alert.sessionID)|\(alert.kind.rawValue)"
        if let previous = recent[key], now.timeIntervalSince(previous) < Self.dedupeWindow {
            return Decision(allowed: false, reason: "doublon")
        }

        if let last = lastDelivery, now.timeIntervalSince(last) < Self.minimumGap {
            return Decision(allowed: false, reason: "débit limité")
        }

        recent[key] = now
        lastDelivery = now
        pruneExpired(now: now)
        return Decision(allowed: true, reason: "")
    }

    /// Drop dedupe entries that can no longer suppress anything, so the map
    /// does not grow with every session ever seen.
    private mutating func pruneExpired(now: Date) {
        guard recent.count > 32 else { return }
        recent = recent.filter { now.timeIntervalSince($0.value) < Self.dedupeWindow }
    }

    public var trackedKeys: Int { recent.count }
}
