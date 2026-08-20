import CoreGraphics
import Foundation
import Observation

/// What the buddy looks like.
///
/// One of three preference models rather than one big one. The reference keeps
/// twenty heterogeneous settings in a single class, so a colour change
/// invalidates everything watching the window position — which is why it has to
/// filter four publishers by hand (`NotchWindow.swift:177-192`). Splitting by
/// *who observes what* is the fix, and it only works if the split is real: this
/// model is read by the buddy renderer and by nothing else.
@MainActor
@Observable
public final class AppearancePrefs {

    public enum Keys {
        public static let buddyID = "notchbuddy.buddy"
        public static let pixelSize = "notchbuddy.appearance.pixelSize"
        public static let overrides = "notchbuddy.buddy.overrides"
    }

    @ObservationIgnored private let store: PreferencesStore

    /// Which manifest is active. The key is the historical one, unchanged: it
    /// is already on every machine that has run this app.
    public var buddyID: String {
        didSet { store.set(buddyID, forKey: Keys.buddyID) }
    }

    /// Backing storage. Private because the clamp is not optional.
    private var storedPixelSize: Double

    /// Device pixels backing one rendered pixel. Higher is blockier.
    ///
    /// Bounded rather than free: past about three the kaomoji stop being
    /// legible, and a preference that can make the buddy unreadable is a
    /// preference that will.
    ///
    /// Computed rather than `didSet`-clamped, and that is not style. Under
    /// `@Observable` a stored property becomes a computed one wrapping the
    /// registrar, so assigning to it from inside its own `didSet` re-enters the
    /// setter instead of being ignored the way it would be on a plain stored
    /// property. The first version of this clamped in `didSet` and recursed
    /// until the stack ran out — a test crashed the whole runner with SIGSEGV.
    public var pixelSize: Double {
        get { storedPixelSize }
        set {
            let clamped = min(max(newValue, 1), 3)
            guard clamped != storedPixelSize else { return }
            storedPixelSize = clamped
            store.set(clamped, forKey: Keys.pixelSize)
        }
    }

    /// Per-expression edits, layered over whatever the `.buddy` file says.
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

    /// A manifest with the user's edits applied.
    public func resolved(_ manifest: BuddyManifest) -> BuddyManifest {
        overrides.apply(to: manifest)
    }
}
