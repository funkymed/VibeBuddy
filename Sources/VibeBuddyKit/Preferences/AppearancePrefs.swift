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

    /// Set while `reload()` re-reads the store, so no `didSet` writes back the
    /// keys a reset has just removed.
    @ObservationIgnored private var isReloading = false

    /// Which manifest is active. Historical key, unchanged: already on disk.
    public var buddyID: String = BuiltInBuddy.id {
        didSet { persist(buddyID, Keys.buddyID) }
    }




    public init(store: PreferencesStore) {
        self.store = store
        reload()
    }

    /// Re-read the store in place. Reallocating the model instead would strand
    /// every view that captured the old one — the settings window keeps it by
    /// value and never rebuilds.
    public func reload() {
        isReloading = true
        defer { isReloading = false }
        buddyID = store.string(Keys.buddyID, default: BuiltInBuddy.id) ?? BuiltInBuddy.id
        // The buddy edit layer was removed on 2026-08-21 with the editor that
        // fed it. Its key is dropped here rather than left behind: a preference
        // nothing reads is a preference that comes back to life the day someone
        // reintroduces the name.
        if store.data(Keys.overrides) != nil { store.remove(Keys.overrides) }
    }

    private func persist(_ value: Any, _ key: String) {
        guard !isReloading else { return }
        store.set(value, forKey: key)
    }


    /// The manifest as it will be drawn — which is the manifest, unchanged.
    ///
    /// Kept as a seam rather than inlined at the call sites: it was the edit
    /// layer's hook, and it is where a per-company buddy override would go if
    /// one is ever wanted. Empty is the honest state, not a placeholder.
    public func resolved(_ manifest: BuddyManifest) -> BuddyManifest { manifest }

}
