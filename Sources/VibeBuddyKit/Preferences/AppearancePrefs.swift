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



    public var overrides = BuddyOverrides() {
        didSet { persistOverrides() }
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
        overrides = BuddyOverrides.decode(store.data(Keys.overrides))
    }

    private func persist(_ value: Any, _ key: String) {
        guard !isReloading else { return }
        store.set(value, forKey: key)
    }

    private func persistOverrides() {
        guard !isReloading, let data = overrides.encoded() else { return }
        store.set(data, forKey: Keys.overrides)
    }

    /// The manifest as it will be drawn — the user's own edits applied, and
    /// **nothing else**. The pill's size is not applied here on purpose:
    /// `scaled` re-rasterises the face onto a different number of cells, so a
    /// wider pill used to mean differently-shaped eyes, not bigger ones.
    public func resolved(_ manifest: BuddyManifest) -> BuddyManifest {
        overrides.apply(to: manifest)
    }

}
