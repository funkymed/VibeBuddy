import Foundation

/// The only thing in this app allowed to create a timer. One `DispatchSourceTimer` at
/// the shortest registered cadence; longer clients are skipped until due, so ten `.lazy`
/// clients cost one wakeup per 30 s. 25 % leeway lets the kernel coalesce.
@MainActor
public final class WakeCoordinator {
    /// Higher values coalesce better; too high and a 1 s cadence visibly drifts.
    private static let leewayFraction: Double = 0.25

    private struct Entry {
        let id: String
        var cadence: Cadence
        var lastFired: TimeInterval
        let onWake: @MainActor () -> Void
    }

    private var entries: [String: Entry] = [:]
    private var timer: DispatchSourceTimer?
    private var scheduledInterval: TimeInterval?

    public private(set) var isSuspended = false

    public private(set) var tickCount: Int = 0

    public init() {}

    public func register(
        id: String,
        cadence: Cadence,
        onWake: @escaping @MainActor () -> Void
    ) {
        entries[id] = Entry(
            id: id,
            cadence: cadence,
            lastFired: Self.now(),
            onWake: onWake
        )
        reschedule()
    }

    public func setCadence(_ cadence: Cadence, for id: String) {
        guard var entry = entries[id], entry.cadence != cadence else { return }
        entry.cadence = cadence
        entries[id] = entry
        reschedule()
    }

    public func unregister(id: String) {
        guard entries.removeValue(forKey: id) != nil else { return }
        reschedule()
    }

    public func cadence(for id: String) -> Cadence? {
        entries[id]?.cadence
    }

    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        reschedule()
    }

    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        // Reset the clocks so waking does not fire every overdue client at once.
        let now = Self.now()
        for key in entries.keys {
            entries[key]?.lastFired = now
        }
        reschedule()
    }

    public var effectiveInterval: TimeInterval? { scheduledInterval }

    public var wakeupsPerSecond: Double {
        guard let interval = scheduledInterval, interval > 0 else { return 0 }
        return 1 / interval
    }

    public nonisolated static func effectiveInterval(for cadences: [Cadence]) -> TimeInterval? {
        cadences.compactMap(\.interval).min()
    }

    private func reschedule() {
        let target = isSuspended
            ? nil
            : Self.effectiveInterval(for: entries.values.map(\.cadence))

        guard target != scheduledInterval else { return }

        timer?.cancel()
        timer = nil
        scheduledInterval = target

        guard let interval = target else { return }

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * Self.leewayFraction * 1000))
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        source.resume()
        timer = source
    }

    private func tick() {
        tickCount += 1
        let now = Self.now()
        for (key, entry) in entries {
            guard let interval = entry.cadence.interval else { continue }
            // Tolerate the leeway we asked for, otherwise a client whose cadence equals
            // the tick interval skips every other tick.
            let due = now - entry.lastFired >= interval * (1 - Self.leewayFraction)
            guard due else { continue }
            entries[key]?.lastFired = now
            entry.onWake()
        }
    }

    /// Monotonic clock: wall time would let a clock change fire every client at once, or
    /// stall them for hours.
    private nonisolated static func now() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
