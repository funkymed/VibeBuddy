import SwiftUI
import VibeBuddyKit

/// The settings window: a sidebar, and one section at a time.
///
/// See RFC-010, "Notes d'implémentation".
struct SettingsShell: View {

    @Bindable var l10n: Localisation
    let appearance: AppearancePrefs
    let layout: LayoutPrefs
    let notifications: NotificationPrefs
    let onLanguageChange: () -> Void
    let onReset: () -> Void
    /// Which pane is showing. Owned by `SettingsWindow` rather than by this
    /// view: the window is reused across openings — `show()` brings the
    /// existing one to the front instead of building a new one — so a `@State`
    /// here survives from one visit to the next and the window reopens wherever
    /// it was left. Held outside, it can be reset each time the window is
    /// shown, which is the whole point.
    @Bindable var navigation: SettingsNavigation

    enum Tab: String, CaseIterable, Identifiable {
        case general, buddy, notifications, sessions, display, permissions, advanced, about
        var id: String { rawValue }

        /// Everything below the separator in the sidebar.
        var isAdvanced: Bool { self == .advanced || self == .about }

        func section(_ s: SettingsStrings) -> SettingsStrings.Section {
            switch self {
            case .general: return s.general
            case .buddy: return s.buddy
            case .notifications: return s.notifications
            case .sessions: return s.sessions
            case .display: return s.usage
            case .permissions: return s.permissions
            case .advanced: return s.advanced
            case .about: return s.about
            }
        }
    }

    private var selection: Binding<Tab> {
        Binding(get: { navigation.tab }, set: { navigation.tab = $0 })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(Tab.allCases.filter { !$0.isAdvanced }) { tab in
                    row(tab).tag(tab)
                }
                Section(l10n.settings.advancedGroup) {
                    ForEach(Tab.allCases.filter(\.isAdvanced)) { tab in
                        row(tab).tag(tab)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(selection.wrappedValue.section(l10n.settings).title)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private func row(_ tab: Tab) -> some View {
        let section = tab.section(l10n.settings)
        return Label(section.title, systemImage: section.symbol)
            .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.wrappedValue {
        case .general:
            GeneralSection(l10n: l10n, onLanguageChange: onLanguageChange)
        case .buddy:
            BuddySection(l10n: l10n, appearance: appearance)
        case .notifications:
            NotificationsSection(l10n: l10n, prefs: notifications)
        case .sessions:
            SessionsSection(l10n: l10n, prefs: layout)
        case .display:
            DisplaySection(l10n: l10n, layout: layout)
        case .permissions:
            PermissionsSection(l10n: l10n)
        case .advanced:
            AdvancedSection(l10n: l10n, onReset: onReset)
        case .about:
            AboutSection(l10n: l10n)
        }
    }
}
