import Foundation
import Observation

/// What the pill and the panel show, and how they behave.
@MainActor
@Observable
public final class LayoutPrefs {
    public enum Keys {
        public static let showPillWithoutSession = "vibebuddy.layout.pillWithoutSession"
        public static let groupByDirectory = "vibebuddy.layout.groupByDirectory"
        public static let jumpOnClick = "vibebuddy.layout.jumpOnClick"
        public static let showUsage = "vibebuddy.layout.showUsage"
    }

    @ObservationIgnored private let store: PreferencesStore

    /// Set while `reload()` re-reads the store, so no `didSet` writes back the keys a
    /// reset has just removed.
    @ObservationIgnored private var isReloading = false

    /// Keep the pill on screen when nothing is running.
    public var showPillWithoutSession: Bool = true {
        didSet { persist(showPillWithoutSession, Keys.showPillWithoutSession) }
    }

    /// One row per directory rather than one per transcript.
    public var groupByDirectory: Bool = true {
        didSet { persist(groupByDirectory, Keys.groupByDirectory) }
    }

    public var jumpOnClick: Bool = true {
        didSet { persist(jumpOnClick, Keys.jumpOnClick) }
    }

    public var showUsage: Bool = true {
        didSet { persist(showUsage, Keys.showUsage) }
    }

    public init(store: PreferencesStore) {
        self.store = store
        reload()
    }

    /// Re-read the store in place; see `AppearancePrefs.reload()`.
    public func reload() {
        isReloading = true
        defer { isReloading = false }
        showPillWithoutSession = store.bool(Keys.showPillWithoutSession, default: true)
        groupByDirectory = store.bool(Keys.groupByDirectory, default: true)
        jumpOnClick = store.bool(Keys.jumpOnClick, default: true)
        showUsage = store.bool(Keys.showUsage, default: true)
    }

    private func persist(_ value: Any, _ key: String) {
        guard !isReloading else { return }
        store.set(value, forKey: key)
    }
}
