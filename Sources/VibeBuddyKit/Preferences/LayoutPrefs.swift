import Foundation
import Observation

/// What the pill and the panel show, and how they behave. Read by the window
/// and the panel, never by the buddy renderer.
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

    /// Keep the pill on screen when nothing is running. Defaults to on, which
    /// diverges from D7 — see RFC-001, "Notes d'implémentation".
    public var showPillWithoutSession: Bool {
        didSet { store.set(showPillWithoutSession, forKey: Keys.showPillWithoutSession) }
    }

    /// One row per directory rather than one per transcript.
    public var groupByDirectory: Bool {
        didSet { store.set(groupByDirectory, forKey: Keys.groupByDirectory) }
    }

    public var jumpOnClick: Bool {
        didSet { store.set(jumpOnClick, forKey: Keys.jumpOnClick) }
    }

    public var showUsage: Bool {
        didSet { store.set(showUsage, forKey: Keys.showUsage) }
    }

    public init(store: PreferencesStore) {
        self.store = store
        showPillWithoutSession = store.bool(Keys.showPillWithoutSession, default: true)
        groupByDirectory = store.bool(Keys.groupByDirectory, default: true)
        jumpOnClick = store.bool(Keys.jumpOnClick, default: true)
        showUsage = store.bool(Keys.showUsage, default: true)
    }
}
