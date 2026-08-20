import Foundation
import Testing
@testable import VibeBuddyKit

/// Preferences, and the two properties that matter: they survive, and they do
/// not write sixty times when they change sixty times.
@Suite("Preferences")
@MainActor
struct PreferencesTests {

    /// A private suite per test, so nothing here can read — or corrupt — the
    /// developer's own settings.
    /// A private suite, wiped afterwards.
    ///
    /// Wiped because a suite that is merely created leaves a plist in
    /// `~/Library/Preferences` for good: a few hundred runs of this file turned
    /// that directory into a landfill of `vibebuddy.tests.<uuid>.plist`.
    private func withStore(_ body: (PreferencesStore, UserDefaults) -> Void) {
        let name = "vibebuddy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        // No legacy domain: these tests are about defaults and coalescing,
        // not about what a previous install left behind.
        body(PreferencesStore(defaults: defaults, previous: nil), defaults)
    }

    @Test("a value reads back before it has been flushed")
    func readsPending() {
        withStore { store, defaults in
            store.set(true, forKey: "k")
            // Not on disk yet…
            #expect(defaults.object(forKey: "k") == nil)
            // …but the UI must never see a stale setting.
            #expect(store.bool("k", default: false))
            store.flush()
            #expect(defaults.bool(forKey: "k"))
        }
    }

    // The reference implementation writes from `didSet` on twenty properties,
    // which is one synchronous write per frame while a window is dragged.
    @Test("a burst of changes collapses into one write")
    func coalesces() {
        withStore { store, _ in
            for value in 0..<60 { store.set(Double(value), forKey: "slider") }
            #expect(store.writeCount == 0)
            store.flush()
            #expect(store.writeCount == 1)
            #expect(store.double("slider", default: 0) == 59)
        }
    }

    @Test("flushing nothing writes nothing")
    func emptyFlush() {
        withStore { store, _ in
            store.flush()
            #expect(store.writeCount == 0)
        }
    }

    @Test("defaults are the documented ones")
    func defaults() {
        withStore { store, _ in
            let notifications = NotificationPrefs(store: store)
            #expect(notifications.onFinished)
            #expect(notifications.onNeedsAttention)
            #expect(notifications.quietWhenFrontmost)
            // Off by default: the speech engine costs megabytes on first use.
            #expect(notifications.voice == false)
            #expect(notifications.haptics == false)

            let appearance = AppearancePrefs(store: store)
            #expect(appearance.pixelSize == 2)
        }
    }

    @Test("every alert kind can be silenced independently")
    func allowsPerKind() {
        withStore { store, _ in
            let prefs = NotificationPrefs(store: store)
            prefs.onFailed = false
            #expect(prefs.allows(.finished))
            #expect(prefs.allows(.needsAttention))
            #expect(prefs.allows(.failed) == false)
        }
    }

    // Past three the kaomoji stop being legible, so the value is clamped rather
    // than trusted — a preference that can make the buddy unreadable will.
    @Test("the pixel grain is bounded")
    func pixelSizeIsClamped() {
        withStore { store, _ in
            let appearance = AppearancePrefs(store: store)
            appearance.pixelSize = 12
            #expect(appearance.pixelSize == 3)
            appearance.pixelSize = 0.1
            #expect(appearance.pixelSize == 1)
        }
    }

    @Test("resetting removes the key rather than storing a default")
    func removeClears() {
        withStore { store, defaults in
            store.set("emoji", forKey: AppearancePrefs.Keys.buddyID)
            store.flush()
            store.remove(AppearancePrefs.Keys.buddyID)
            #expect(defaults.object(forKey: AppearancePrefs.Keys.buddyID) == nil)
            #expect(store.string(AppearancePrefs.Keys.buddyID, default: "orb") == "orb")
        }
    }
}

/// Renaming a key prefix moves settings nobody has a copy of.
@Suite("Preferences migration")
@MainActor
struct PreferencesMigrationTests {

    /// Same rule as the suite above: created, used, wiped.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "vibebuddy.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test("values stored under the old prefix are carried over")
    func carriesValues() {
        withDefaults { store in
            store.set("emoji", forKey: "notchbuddy.buddy")
            store.set(false, forKey: "notchbuddy.alerts.voice")

                _ = PreferencesStore(defaults: store, previous: nil)

            #expect(store.string(forKey: "vibebuddy.buddy") == "emoji")
            #expect(store.object(forKey: "vibebuddy.alerts.voice") as? Bool == false)
            // And the old ones are gone, so a later downgrade cannot resurrect them.
            #expect(store.object(forKey: "notchbuddy.buddy") == nil)
            #expect(store.integer(forKey: PreferencesStore.schemaKey) == PreferencesStore.schema)
        }
    }

    // A value already stored under the new name is the newer one. Copying over
    // it would undo whatever the user changed since the first migration.
    @Test("an existing value wins over the legacy one")
    func doesNotOverwrite() {
        withDefaults { store in
            store.set("emoji", forKey: "notchbuddy.buddy")
            store.set("orb", forKey: "vibebuddy.buddy")

                _ = PreferencesStore(defaults: store, previous: nil)

            #expect(store.string(forKey: "vibebuddy.buddy") == "orb")
            #expect(store.object(forKey: "notchbuddy.buddy") == nil)
        }
    }

    @Test("a fresh install migrates nothing and still stamps the schema")
    func freshInstall() {
        withDefaults { store in
                _ = PreferencesStore(defaults: store, previous: nil)
            #expect(store.integer(forKey: PreferencesStore.schemaKey) == PreferencesStore.schema)
            #expect(store.object(forKey: "vibebuddy.buddy") == nil)
        }
    }

    @Test("running it twice changes nothing the second time")
    func idempotent() {
        withDefaults { store in
            store.set("emoji", forKey: "notchbuddy.buddy")
                _ = PreferencesStore(defaults: store, previous: nil)
                _ = PreferencesStore(defaults: store, previous: nil)
            #expect(store.string(forKey: "vibebuddy.buddy") == "emoji")
        }
    }
}
