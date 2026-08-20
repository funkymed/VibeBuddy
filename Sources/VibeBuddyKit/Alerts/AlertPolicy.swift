import Foundation

/// Decides whether an alert actually reaches the user.
public struct AlertPolicy: Sendable {

    /// Minimum gap between two visual alerts, whatever their source: three
    /// sessions finishing at once produce one interruption, not three.
    public static let minimumGap: TimeInterval = 12

    /// Window in which the same session repeating the same alert counts as one
    /// event. Guards a rewritten transcript (compaction) replaying a completion.
    public static let dedupeWindow: TimeInterval = 60

    public struct Decision: Sendable, Equatable {
        public let allowed: Bool
        public let reason: String
    }

    private var lastDelivery: Date?
    private var recent: [String: Date] = [:]

    public init() {}

    /// - Parameter hostingTerminalIsFrontmost: the user is already looking at
    ///   this terminal, so the alert would be noise.
    public mutating func admit(
        _ alert: SessionAlert,
        now: Date,
        hostingTerminalIsFrontmost: Bool
    ) -> Decision {
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

    /// Drop dedupe entries that can no longer suppress anything.
    private mutating func pruneExpired(now: Date) {
        guard recent.count > 32 else { return }
        recent = recent.filter { now.timeIntervalSince($0.value) < Self.dedupeWindow }
    }

    public var trackedKeys: Int { recent.count }
}
