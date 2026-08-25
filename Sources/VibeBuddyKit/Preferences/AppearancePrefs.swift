import CoreGraphics
import Foundation
import Observation

/// What the buddy looks like.
@MainActor
@Observable
public final class AppearancePrefs {
    public enum Keys {
        public static let buddyID = "vibebuddy.buddy"
        public static let overrides = "vibebuddy.buddy.overrides"
    }

    @ObservationIgnored private let store: PreferencesStore

    /// Set while `reload()` re-reads the store, so no `didSet` writes back the keys a
    /// reset has just removed.
    @ObservationIgnored private var isReloading = false

    /// Which manifest is active.
    public var buddyID: String = BuiltInBuddy.id {
        didSet { persist(buddyID, Keys.buddyID) }
    }

    public init(store: PreferencesStore) {
        self.store = store
        reload()
    }

    /// Re-read the store in place.
    public func reload() {
        isReloading = true
        defer { isReloading = false }
        buddyID = store.string(Keys.buddyID, default: BuiltInBuddy.id) ?? BuiltInBuddy.id
        // The buddy edit layer was removed on 2026-08-21 with the editor that fed it.
        if store.data(Keys.overrides) != nil { store.remove(Keys.overrides) }
    }

    private func persist(_ value: Any, _ key: String) {
        guard !isReloading else { return }
        store.set(value, forKey: key)
    }

}
