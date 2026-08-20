import CoreGraphics
import Foundation
import Observation

/// What the buddy looks like.
@MainActor
@Observable
public final class AppearancePrefs {

    public enum Keys {
        public static let buddyID = "vibebuddy.buddy"
        public static let pixelSize = "vibebuddy.appearance.pixelSize"
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

    private var storedPixelSize: Double = 2

    /// Device pixels backing one rendered pixel, bounded to 1…3: past three the
    /// kaomoji stop being legible.
    ///
    /// Do not clamp in `didSet`. Under `@Observable` a stored property becomes a
    /// computed one, so assigning from inside its own `didSet` re-enters the
    /// setter and recurses until the stack runs out (SIGSEGV in a test).
    public var pixelSize: Double {
        get { storedPixelSize }
        set {
            let clamped = min(max(newValue, 1), 3)
            guard clamped != storedPixelSize else { return }
            storedPixelSize = clamped
            store.set(clamped, forKey: Keys.pixelSize)
        }
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
        storedPixelSize = min(max(store.double(Keys.pixelSize, default: 2), 1), 3)
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

    public func resolved(_ manifest: BuddyManifest) -> BuddyManifest {
        overrides.apply(to: manifest)
    }
}
