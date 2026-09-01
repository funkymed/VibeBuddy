import Foundation
import Observation

/// Whether a newer version exists, and when that was last asked.
///
/// Deliberately does not download, install, or nag. It knows one fact and where to send
/// somebody who wants to act on it — the app is not notarised, so a binary it fetched
/// itself would arrive quarantined and the user would have to run `xattr` on something
/// they never chose to download.
@MainActor
@Observable
public final class UpdateState {
    public enum Keys {
        public static let enabled = "vibebuddy.update.check"
        public static let lastCheck = "vibebuddy.update.lastCheck"
    }

    /// A day. Nobody ships fast enough for this to matter, and a check per launch would
    /// spend somebody else's rate limit on nothing.
    public static let interval: TimeInterval = 24 * 3600

    /// Delay before the first check of a launch. Long enough to be out of the way of
    /// everything that has to happen for the pill to appear.
    public static let launchDelay: TimeInterval = 20

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let checker: ReleaseChecker
    @ObservationIgnored private let current: ReleaseVersion?
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var inFlight = false

    /// The newer release, when there is one. Nil covers « up to date », « never asked »
    /// and « could not ask » alike: none of the three has anything to show.
    public private(set) var available: LatestRelease?

    public var isEnabled: Bool = true {
        didSet {
            guard !isReloading, isEnabled != oldValue else { return }
            store.set(isEnabled, forKey: Keys.enabled)
            // Turning it off takes the notice away with it, rather than leaving the last
            // answer on screen under a switch that says nothing is being asked.
            if !isEnabled { available = nil }
        }
    }

    public init(
        store: PreferencesStore,
        currentVersion: String,
        checker: ReleaseChecker = ReleaseChecker()
    ) {
        self.store = store
        self.checker = checker
        self.current = ReleaseVersion(currentVersion)
        reload()
    }

    public func reload() {
        isReloading = true
        defer { isReloading = false }
        isEnabled = store.bool(Keys.enabled, default: true)
    }

    public var lastCheck: Date? {
        let stamp = store.double(Keys.lastCheck, default: 0)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Whether a check is due. Off, or asked within the last day, means no.
    public func isDue(now: Date = Date()) -> Bool {
        guard isEnabled, !inFlight else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= Self.interval
    }

    /// Asks, if it is due. Silent on every failure: an update check that reports its own
    /// network problems is noise about something nobody asked for.
    public func checkIfDue(now: Date = Date()) async {
        guard isDue(now: now) else { return }
        await check(now: now)
    }

    /// Asks now, whatever the clock says. The settings button.
    public func check(now: Date = Date()) async {
        guard isEnabled, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let outcome = await checker.fetch()
        // Stamped whatever the answer: a machine that is offline for a week must not
        // retry on every wake.
        store.set(now.timeIntervalSince1970, forKey: Keys.lastCheck)

        guard case let .found(release) = outcome, let current else {
            available = nil
            return
        }
        available = release.version > current ? release : nil
    }
}
