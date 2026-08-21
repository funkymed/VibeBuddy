import Foundation
import Observation

/// Reads and writes preferences, and never writes more than it has to.
///
/// A change marks a key dirty and schedules one flush; writing straight from
/// `didSet` costs one synchronous write per frame while a window is dragged. The
/// delay is a one-shot `asyncAfter`, not a repeating timer — D3 forbids a second
/// clock. See RFC-001, "Notes d'implémentation".
@MainActor
public final class PreferencesStore {

    /// How long a burst accumulates before it lands. `flush()` also runs on quit.
    public static let coalescingDelay: TimeInterval = 0.25

    /// Current schema. Bump when a key changes meaning, and add a migration.
    public static let schema = 4
    static let schemaKey = "vibebuddy.schema"

    static let legacyPrefix = "notchbuddy."
    static let prefix = "vibebuddy."

    /// Domains this app wrote to before, newest first.
    ///
    /// An unbundled binary keys `UserDefaults.standard` on the executable name,
    /// a bundle keys it on its identifier — so both spellings hold real
    /// settings. Packaging the app moved the domain a second time, and reading
    /// only the oldest one restored values from two renames ago.
    public static let legacyDomains = ["VibeBuddy", "NotchBuddy"]

    private let defaults: UserDefaults
    private var pending: [String: Any] = [:]
    private var scheduled = false
    public private(set) var writeCount = 0

    /// Injectable so tests do not inherit the developer's own settings.
    private let previousDomains: [UserDefaults]

    public init(
        defaults: UserDefaults = .standard,
        previous: [UserDefaults] = PreferencesStore.legacyDomains
            .compactMap { UserDefaults(suiteName: $0) }
    ) {
        self.defaults = defaults
        self.previousDomains = previous
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

    public func set(_ value: Any, forKey key: String) {
        pending[key] = value
        schedule()
    }

    public func remove(_ key: String) {
        pending.removeValue(forKey: key)
        defaults.removeObject(forKey: key)
    }

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

    /// Schema 2 renames every key's prefix. No file holds a copy of these values,
    /// so copy before deleting, and delete only what was copied.
    private func migrate() {
        let stored = defaults.integer(forKey: Self.schemaKey)
        guard stored != Self.schema else { return }

        if stored < 4 {
            for key in Self.allKeys where key.hasPrefix(Self.prefix) {
                let legacy = Self.legacyPrefix + key.dropFirst(Self.prefix.count)
                // This domain under the old prefix first, then each previous
                // domain in order of recency, under either prefix.
                var value = defaults.object(forKey: legacy)
                if value == nil {
                    for domain in previousDomains {
                        value = domain.object(forKey: key) ?? domain.object(forKey: legacy)
                        if value != nil { break }
                    }
                }
                guard let value else { continue }
                // Schema 4 overwrites what schema 3 wrote: that pass read the
                // oldest domain only, so a value already present here can be two
                // renames stale.
                if stored == 3 || defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
                defaults.removeObject(forKey: legacy)
            }
        }

        defaults.set(Self.schema, forKey: Self.schemaKey)
    }

    /// Every key this app owns, for "reset everything". Listed, not derived: the
    /// domain also holds system keys a wipe would take with it.
    public static let allKeys: [String] = [
        schemaKey,
        AppearancePrefs.Keys.buddyID,
        AppearancePrefs.Keys.overrides,
        LayoutPrefs.Keys.showPillWithoutSession, LayoutPrefs.Keys.groupByDirectory,
        LayoutPrefs.Keys.jumpOnClick, LayoutPrefs.Keys.showUsage,
        NotificationPrefs.Keys.onFinished, NotificationPrefs.Keys.onFailed,
        NotificationPrefs.Keys.onNeedsAttention, NotificationPrefs.Keys.voice,
        NotificationPrefs.Keys.haptics, NotificationPrefs.Keys.quietWhenFrontmost,
        // Ours too, though they bypass this store (schema 3).
        Localisation.storageKey,
        UsageCache.key,
        selectedSettingsTabKey,
    ]

    public static let selectedSettingsTabKey = "vibebuddy.settings.tab"
}
