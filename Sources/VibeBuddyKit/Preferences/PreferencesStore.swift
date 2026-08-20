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
    public static let schema = 3
    static let schemaKey = "vibebuddy.schema"

    /// Prefix the keys carried before schema 2.
    static let legacyPrefix = "notchbuddy."
    static let prefix = "vibebuddy."

    /// Domain the settings lived in before the executable was renamed.
    ///
    /// For an unbundled binary `UserDefaults.standard` is keyed on the
    /// executable's name, so renaming the binary moves every setting to a new
    /// plist and the old one keeps the user's answers. Renaming the key prefix
    /// alone would migrate an empty file onto an empty file and look like it
    /// worked.
    public static let legacyDomain = "NotchBuddy"

    private let defaults: UserDefaults
    private var pending: [String: Any] = [:]
    private var scheduled = false
    /// Counts writes that actually reached `UserDefaults`, so a test can prove
    /// a drag produces one and not sixty.
    public private(set) var writeCount = 0

    /// Where settings written by the previous executable name still sit.
    ///
    /// Injectable so tests are hermetic: with the real domain as a hard-coded
    /// default, every test that opened a fresh suite inherited the developer's
    /// own settings through the migration and asserted against them.
    private let previous: UserDefaults?

    public init(
        defaults: UserDefaults = .standard,
        previous: UserDefaults? = UserDefaults(suiteName: PreferencesStore.legacyDomain)
    ) {
        self.defaults = defaults
        self.previous = previous
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
    /// **Schema 2 renames every key's prefix.** The values are the user's
    /// settings and their buddy edits, which no file holds a copy of, so the
    /// rename copies before it deletes and only deletes what it managed to
    /// copy. Renaming keys without this is indistinguishable, from where the
    /// user sits, from the app forgetting everything.
    private func migrate() {
        let stored = defaults.integer(forKey: Self.schemaKey)
        guard stored != Self.schema else { return }

        if stored < 3 {
            for key in Self.allKeys where key.hasPrefix(Self.prefix) {
                let legacy = Self.legacyPrefix + key.dropFirst(Self.prefix.count)
                // Three places to look, newest first: this domain under the old
                // prefix, then the domain the previous executable name wrote to,
                // under either prefix.
                let value = defaults.object(forKey: legacy)
                    ?? previous?.object(forKey: legacy)
                    ?? previous?.object(forKey: key)
                guard let value else { continue }
                // Never overwrite a value already stored under the new name: a
                // second run must not resurrect what the first one replaced.
                if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
                defaults.removeObject(forKey: legacy)
            }
        }

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
        // Settings that do not go through this store but are ours all the same:
        // they have to migrate with the rest, and a reset has to clear them.
        // Schema 3 exists because the first pass forgot them and stranded the
        // language in the previous domain.
        Localisation.storageKey,
        UsageCache.key,
        selectedSettingsTabKey,
    ]

    /// Which settings section is showing. Written by `@AppStorage` in the
    /// window, listed here so migration and reset know about it.
    public static let selectedSettingsTabKey = "vibebuddy.settings.tab"
}
