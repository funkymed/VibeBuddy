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

    /// Which manifest is active. Historical key, unchanged: already on disk.
    public var buddyID: String {
        didSet { store.set(buddyID, forKey: Keys.buddyID) }
    }

    private var storedPixelSize: Double

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

    public var overrides: BuddyOverrides {
        didSet { persistOverrides() }
    }

    public init(store: PreferencesStore) {
        self.store = store
        buddyID = store.string(Keys.buddyID, default: "emoji") ?? "emoji"
        storedPixelSize = min(max(store.double(Keys.pixelSize, default: 2), 1), 3)
        overrides = BuddyOverrides.decode(store.data(Keys.overrides))
    }

    private func persistOverrides() {
        guard let data = overrides.encoded() else { return }
        store.set(data, forKey: Keys.overrides)
    }

    public func resolved(_ manifest: BuddyManifest) -> BuddyManifest {
        overrides.apply(to: manifest)
    }
}
