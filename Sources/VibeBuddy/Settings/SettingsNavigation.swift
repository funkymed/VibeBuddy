import Observation

/// Which settings pane is showing.
@MainActor
@Observable
final class SettingsNavigation {
    var tab: SettingsShell.Tab = .general
}
