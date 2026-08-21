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
    let onBuddyChange: (String?) -> Void
    let onLanguageChange: () -> Void
    let onReset: () -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case general, buddy, notifications, sessions, display, advanced, about
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
            case .advanced: return s.advanced
            case .about: return s.about
            }
        }
    }

    @AppStorage("vibebuddy.settings.tab") private var selectedRaw: String = Tab.general.rawValue

    private var selection: Binding<Tab> {
        Binding(
            get: { Tab(rawValue: selectedRaw) ?? .general },
            set: { selectedRaw = $0.rawValue })
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
            BuddySection(
                l10n: l10n, appearance: appearance, onBuddyChange: onBuddyChange)
        case .notifications:
            NotificationsSection(l10n: l10n, prefs: notifications)
        case .sessions:
            SessionsSection(l10n: l10n, prefs: layout)
        case .display:
            DisplaySection(l10n: l10n, layout: layout)
        case .advanced:
            AdvancedSection(l10n: l10n, onReset: onReset)
        case .about:
            AboutSection(l10n: l10n, appearance: appearance)
        }
    }
}
