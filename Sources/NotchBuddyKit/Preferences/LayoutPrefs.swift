import Foundation
import Observation

/// What the pill and the panel show, and how they behave.
///
/// Separate from `AppearancePrefs` for the reason that model states: these are
/// read by the window and the panel, and a buddy colour change must not make
/// either of them recompute a frame.
@MainActor
@Observable
public final class LayoutPrefs {

    public enum Keys {
        public static let showPillWithoutSession = "notchbuddy.layout.pillWithoutSession"
        public static let groupByDirectory = "notchbuddy.layout.groupByDirectory"
        public static let jumpOnClick = "notchbuddy.layout.jumpOnClick"
        public static let showUsage = "notchbuddy.layout.showUsage"
    }

    @ObservationIgnored private let store: PreferencesStore

    /// Keep the pill on screen when nothing is running.
    ///
    /// D7 says this should default to off. It defaults to **on** here, and that
    /// is a deliberate divergence rather than an oversight: the app has always
    /// shown the pill, and silently making it disappear on upgrade would read as
    /// a crash rather than as a new default. The toggle exists; the default
    /// moves the day the app ships to someone who never saw the old behaviour.
    public var showPillWithoutSession: Bool {
        didSet { store.set(showPillWithoutSession, forKey: Keys.showPillWithoutSession) }
    }

    /// One row per directory rather than one per transcript.
    public var groupByDirectory: Bool {
        didSet { store.set(groupByDirectory, forKey: Keys.groupByDirectory) }
    }

    /// Clicking a live row brings its terminal forward.
    public var jumpOnClick: Bool {
        didSet { store.set(jumpOnClick, forKey: Keys.jumpOnClick) }
    }

    /// Show the two usage gauges at the foot of the panel.
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
