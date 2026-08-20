import Foundation
import Observation

/// Reads and writes preferences, and never writes more than it has to.
///
/// # Why not `@AppStorage`
///
/// `@AppStorage` has no migration path. The reference implementation needed one
/// the moment it changed how a window position was stored, and hand-rolled it
/// (`BuddyPreferences.swift:79-91`); a store that cannot version its own keys
/// simply defers that work to whoever hits it first.
///
/// # Coalesced writes
///
/// The reference writes to `UserDefaults` from `didSet` on twenty properties
/// (`NotchWindow.swift:505-507`), which means a synchronous write **per frame**
/// while a window is dragged. Here a change marks a key dirty and schedules one
/// flush; a burst of changes collapses into a single write.
///
/// The delay is a **one-shot** `asyncAfter`, not a repeating timer: D3 forbids a
/// second clock, and this is not one — nothing is scheduled unless a preference
/// actually changed, and at rest the store is silent.
@MainActor
public final class PreferencesStore {

    /// How long a burst of changes is allowed to accumulate before it lands.
    ///
    /// Long enough to swallow a slider drag, short enough that quitting right
    /// after a change cannot lose it — `flush()` is also called on termination.
    public static let coalescingDelay: TimeInterval = 0.25

    /// Current schema. Bump when a key changes meaning, and add a migration.
    public static let schema = 1
    static let schemaKey = "notchbuddy.schema"

    private let defaults: UserDefaults
    private var pending: [String: Any] = [:]
    private var scheduled = false
    /// Counts writes that actually reached `UserDefaults`, so a test can prove
    /// a drag produces one and not sixty.
    public private(set) var writeCount = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrate()
    }

    // MARK: - Reading

    public func bool(_ key: String, default fallback: Bool) -> Bool {
        if let pendingValue = pending[key] as? Bool { return pendingValue }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    public func double(_ key: String, default fallback: Double) -> Double {
        if let pendingValue = pending[key] as? Double { return pendingValue }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    public func string(_ key: String, default fallback: String?) -> String? {
        if let pendingValue = pending[key] as? String { return pendingValue }
        return defaults.string(forKey: key) ?? fallback
    }

    public func data(_ key: String) -> Data? {
        if let pendingValue = pending[key] as? Data { return pendingValue }
        return defaults.data(forKey: key)
    }

    // MARK: - Writing

    /// Queue a value. The read accessors serve the pending value immediately, so
    /// the UI never sees a stale setting while the write is in flight.
    public func set(_ value: Any, forKey key: String) {
        pending[key] = value
        schedule()
    }

    public func remove(_ key: String) {
        pending.removeValue(forKey: key)
        defaults.removeObject(forKey: key)
    }

    /// Write everything queued, now. Called on quit and when the settings window
    /// closes — the two moments where waiting a quarter second is a real risk.
    public func flush() {
        guard !pending.isEmpty else { return }
        for (key, value) in pending { defaults.set(value, forKey: key) }
        writeCount += 1
        pending = [:]
        scheduled = false
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalescingDelay) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    // MARK: - Migration

    /// Bring an older layout forward.
    ///
    /// Empty today, and deliberately present anyway: the cost of adding the
    /// frame now is one function, and the cost of adding it later is discovering
    /// mid-release that a key changed meaning for people who already have it.
    private func migrate() {
        let stored = defaults.integer(forKey: Self.schemaKey)
        guard stored != Self.schema else { return }
        // No migration to run yet — schema 0 (absent) and 1 are the same shape.
        defaults.set(Self.schema, forKey: Self.schemaKey)
    }

    /// Every key this app owns, for "reset everything".
    ///
    /// Listed rather than derived from the domain: `UserDefaults.standard` also
    /// holds system-managed keys for this bundle, and wiping the domain would
    /// take those with it.
    public static let allKeys: [String] = [
        schemaKey,
        AppearancePrefs.Keys.buddyID, AppearancePrefs.Keys.pixelSize,
        AppearancePrefs.Keys.overrides,
        LayoutPrefs.Keys.showPillWithoutSession, LayoutPrefs.Keys.groupByDirectory,
        LayoutPrefs.Keys.jumpOnClick, LayoutPrefs.Keys.showUsage,
        NotificationPrefs.Keys.onFinished, NotificationPrefs.Keys.onFailed,
        NotificationPrefs.Keys.onNeedsAttention, NotificationPrefs.Keys.voice,
        NotificationPrefs.Keys.haptics, NotificationPrefs.Keys.quietWhenFrontmost,
    ]
}
