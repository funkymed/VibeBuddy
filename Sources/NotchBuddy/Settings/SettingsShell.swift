import SwiftUI
import NotchBuddyKit

/// The settings window: a sidebar, and one section at a time.
///
/// # Why segmented rather than one form
///
/// What shipped first was a single `Form` with two sections. Everything the open
/// RFCs are about to add — login item, alerts per event, voice, terminal jump,
/// usage, diagnostics — lands in that same form, and a form of twenty
/// heterogeneous rows is the UI version of the monolith RFC-010 spends its first
/// page criticising in the *model*.
///
/// # One section mounted at a time
///
/// `NavigationSplitView` builds only the selected detail, so the buddy editor's
/// timeline does not exist while someone is reading the About page. That is the
/// whole animation budget of this window: one clock, in the one place where
/// motion is the subject.
struct SettingsShell: View {

    @Bindable var l10n: Localisation
    let appearance: AppearancePrefs
    let layout: LayoutPrefs
    let notifications: NotificationPrefs
    let onBuddyChange: (String?) -> Void
    let onLanguageChange: () -> Void
    let onReset: () -> Void

    /// Sections with nothing behind them are not listed at all.
    ///
    /// A section that promises a subject and delivers an empty page is worse
    /// than one that is absent — same rule as the panel, which shows no heatmap
    /// because RFC-009 does not exist.
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

    /// Persisted so reopening the window returns where it was left. A settings
    /// window that always reopens on page one makes changing two related
    /// settings a navigation exercise.
    @AppStorage("notchbuddy.settings.tab") private var selectedRaw: String = Tab.general.rawValue

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
            DisplaySection(l10n: l10n, layout: layout, appearance: appearance)
        case .advanced:
            AdvancedSection(l10n: l10n, onReset: onReset)
        case .about:
            AboutSection(l10n: l10n, appearance: appearance)
        }
    }
}

/// A titled group of rows, used by every section.
///
/// Here rather than in each section so the sections cannot drift apart
/// visually — seven files each inventing their own spacing is how a settings
/// window ends up looking assembled rather than designed.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
        }
    }
}

/// One row: a label, an optional explanation, and a control.
struct SettingsRow<Control: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 10)
    }
}

/// A section's page: a scroll view with consistent padding.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
