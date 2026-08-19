import SwiftUI
import NotchBuddyKit

/// The expanded panel.
///
/// Deliberately short. RFC-001's decision D2 caps a view at 200 lines, because
/// the reference implementation's equivalent is 3 738 and every `@Published`
/// in the app re-evaluates all of it. The header and the row live in their own
/// files for the same reason.
///
/// # What is not here, and why it is not faked
///
/// The reference panel also shows live usage percentages, an activity heatmap
/// and a list of always-allowed tools. Those are RFC-004, RFC-009 and RFC-007,
/// none of them written. They are absent rather than mocked: a placeholder
/// percentage in a product whose selling point is showing the *real* number
/// would be the worst possible thing to ship.
struct PanelContentView: View {
    let sessions: [AgentSession]
    let buddy: BuddyManifest?
    let expression: BuddyExpression
    @Bindable var budget: AnimationBudget
    let usage: UsageState.Status
    let l10n: Strings
    let locale: Locale
    var onSettings: () -> Void
    var onQuit: () -> Void

    @State private var filter = ""

    private var visible: [AgentSession] {
        guard !filter.isEmpty else { return sessions }
        let needle = filter.lowercased()
        return sessions.filter {
            $0.projectName.lowercased().contains(needle)
                || $0.model.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(
                buddy: buddy, expression: expression, sessions: sessions,
                budget: budget, l10n: l10n,
                onSettings: onSettings, onQuit: onQuit
            )

            if sessions.count > 3 { filterField }

            sessionsSection

            Spacer(minLength: 8)

            Divider().overlay(.white.opacity(0.08))
            UsageSection(state: usage, l10n: l10n, locale: locale)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Only shown once the list is long enough to need it. A search box above
    /// two rows is furniture.
    private var filterField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            TextField(l10n.filterPlaceholder, text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.sessionsTitle, count: visible.count)

            if visible.isEmpty {
                emptyState
            } else {
                // Live first, then most recently active. A finished session
                // sinking below a running one is the ordering people expect.
                ForEach(visible.sorted(by: Self.byRelevance)) { session in
                    SessionRow(session: session, l10n: l10n).equatable()
                }
            }
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(0.8)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    private var emptyState: some View {
        Text(filter.isEmpty ? l10n.emptyHint : l10n.noMatch(filter))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.vertical, 10)
    }

    nonisolated static func byRelevance(_ a: AgentSession, _ b: AgentSession) -> Bool {
        if a.isLive != b.isLive { return a.isLive }
        return a.lastActivity > b.lastActivity
    }
}
