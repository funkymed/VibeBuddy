import Foundation
import Testing
@testable import NotchBuddyKit

/// Preferences, and the two properties that matter: they survive, and they do
/// not write sixty times when they change sixty times.
@Suite("Preferences")
@MainActor
struct PreferencesTests {

    /// A private suite per test, so nothing here can read — or corrupt — the
    /// developer's own settings.
    private func makeStore() -> (PreferencesStore, UserDefaults) {
        let name = "notchbuddy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (PreferencesStore(defaults: defaults), defaults)
    }

    @Test("a value reads back before it has been flushed")
    func readsPending() {
        let (store, defaults) = makeStore()
        store.set(true, forKey: "k")
        // Not on disk yet…
        #expect(defaults.object(forKey: "k") == nil)
        // …but the UI must never see a stale setting.
        #expect(store.bool("k", default: false))
        store.flush()
        #expect(defaults.bool(forKey: "k"))
    }

    // The reference implementation writes from `didSet` on twenty properties,
    // which is one synchronous write per frame while a window is dragged.
    @Test("a burst of changes collapses into one write")
    func coalesces() {
        let (store, _) = makeStore()
        for value in 0..<60 { store.set(Double(value), forKey: "slider") }
        #expect(store.writeCount == 0)
        store.flush()
        #expect(store.writeCount == 1)
        #expect(store.double("slider", default: 0) == 59)
    }

    @Test("flushing nothing writes nothing")
    func emptyFlush() {
        let (store, _) = makeStore()
        store.flush()
        #expect(store.writeCount == 0)
    }

    @Test("defaults are the documented ones")
    func defaults() {
        let (store, _) = makeStore()
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

    @Test("every alert kind can be silenced independently")
    func allowsPerKind() {
        let (store, _) = makeStore()
        let prefs = NotificationPrefs(store: store)
        prefs.onFailed = false
        #expect(prefs.allows(.finished))
        #expect(prefs.allows(.needsAttention))
        #expect(prefs.allows(.failed) == false)
    }

    // Past three the kaomoji stop being legible, so the value is clamped rather
    // than trusted — a preference that can make the buddy unreadable will.
    @Test("the pixel grain is bounded")
    func pixelSizeIsClamped() {
        let (store, _) = makeStore()
        let appearance = AppearancePrefs(store: store)
        appearance.pixelSize = 12
        #expect(appearance.pixelSize == 3)
        appearance.pixelSize = 0.1
        #expect(appearance.pixelSize == 1)
    }

    @Test("resetting removes the key rather than storing a default")
    func removeClears() {
        let (store, defaults) = makeStore()
        store.set("emoji", forKey: AppearancePrefs.Keys.buddyID)
        store.flush()
        store.remove(AppearancePrefs.Keys.buddyID)
        #expect(defaults.object(forKey: AppearancePrefs.Keys.buddyID) == nil)
        #expect(store.string(AppearancePrefs.Keys.buddyID, default: "orb") == "orb")
    }
}
