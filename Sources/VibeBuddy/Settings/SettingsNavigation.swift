import Observation

/// Which settings pane is showing.
///
/// Lives outside `SettingsShell` because the window outlives the view: opening
/// the settings a second time brings the same window forward without rebuilding
/// anything, so state held in the view is state that never resets.
@MainActor
@Observable
final class SettingsNavigation {
    var tab: SettingsShell.Tab = .general
}
