import SwiftUI
import VibeBuddyKit

/// The expanded panel. See RFC-008, "Notes d'implémentation".
struct PanelContentView: View {
    let sessions: [AgentSession]
    let buddy: BuddyManifest?
    var buddyBox: CGSize = .zero
    let expression: BuddyExpression
    @Bindable var budget: AnimationBudget
    let usage: UsageState.Status
    let l10n: Strings
    let locale: Locale
    var onSettings: () -> Void
    var onQuit: () -> Void
    var onJump: (pid_t) -> Void = { _ in }
    var onSelect: ((String) -> Void)?
    /// Set only when the last jump has something to say: tab not found,
    /// permission refused.
    var jumpNote: String?
    /// One row per directory rather than one per transcript.
    var groupByDirectory = true
    var jumpOnClick = true
    var showUsage = true


    private var visible: [SessionGroup] {
        // Ungrouped is one group per session, so the row needs no second code path.
        groupByDirectory
            ? SessionGroup.group(sessions)
            : SessionGroup.ungrouped(sessions)
    }

    // The header, the identity line and the padding are `DeployedPanel`'s,
    // shared with every other thing the deployed panel can show.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Keep this frame: without it the list grows and pushes the header
            // above and the usage below off the panel.
            sessionsSection
                .frame(maxHeight: .infinity, alignment: .top)

            if showUsage {
                VibeDivider()
                UsageSection(state: usage, l10n: l10n, locale: locale)
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionTitle(l10n.sessionsTitle, count: visible.count)
                if let jumpNote {
                    Text(jumpNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineLimit(1)
                }
            }

            if visible.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        // Ordering (live first, then recency) is owned by
                        // SessionGroup.group, not by the view.
                        ForEach(visible) { group in
                            SessionRow(
                                group: group, l10n: l10n,
                                onJump: jumpOnClick ? onJump : nil,
                                onSelect: onSelect).equatable()
                        }
                    }
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: VibeTheme.Spacing.s) {
            // Same treatment as `AUTORISATION`: a section label is the panel's
            // way of saying what you are looking at, and there is exactly one
            // colour for « this is VibeBuddy speaking ».
            Text(text)
                .font(VibeTheme.Typography.section)
                .foregroundStyle(VibeTheme.Accent.primary)
                .tracking(VibeTheme.Typography.sectionTracking)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelInk.tertiary)
        }
    }

    private var emptyState: some View {
        Text(l10n.emptyHint)
            .font(.system(size: 13))
            .foregroundStyle(PanelInk.tertiary)
            .padding(.vertical, 12)
    }

}
