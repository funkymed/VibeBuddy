import SwiftUI
import VibeBuddyKit

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
    /// Set only when the last jump has something to say: tab not found, permission
    /// refused.
    var jumpNote: String?
    var timelines = SessionTimelineLoader()
    /// One row per directory rather than one per transcript.
    var groupByDirectory = true
    var jumpOnClick = true
    var showUsage = true

    /// The session whose history is on screen. Held by id rather than by value so a
    /// refresh that rewrites the session keeps the view open on it.
    @State private var openedID: String?

    private var opened: AgentSession? {
        openedID.flatMap { id in sessions.first { $0.id == id } }
    }

    private var visible: [SessionGroup] {
        // Ungrouped is one group per session, so the row needs no second code path.
        groupByDirectory
            ? SessionGroup.group(sessions)
            : SessionGroup.ungrouped(sessions)
    }

    // The header, the identity line and the padding are `DeployedPanel`'s, shared with
    // every other thing the deployed panel can show.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Keep this frame: without it the list grows and pushes the header above
            // and the usage below off the panel.
            Group {
                if let opened {
                    SessionDetailView(session: opened, l10n: l10n, loader: timelines) {
                        openedID = nil
                    }
                } else {
                    sessionsSection
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            // The history replaces the list, not the panel: usage stays where it was.
            if showUsage {
                VibeDivider()
                UsageSection(state: usage, l10n: l10n, locale: locale)
            }
        }
        // A session that ends while its history is open takes the view with it,
        // otherwise the back button is the only way out of a dead end.
        .onChange(of: sessions) { _, now in
            if let id = openedID, !now.contains(where: { $0.id == id }) { openedID = nil }
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
                            HStack(spacing: 4) {
                                SessionRow(
                                    group: group, l10n: l10n,
                                    onJump: jumpOnClick ? onJump : nil,
                                    onSelect: onSelect).equatable()
                                // Outside the row's own button: a button inside a button
                                // gives SwiftUI two overlapping hit targets, and the
                                // inner one wins in ways that depend on the frame.
                                historyButton(for: group.primary)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func historyButton(for session: AgentSession) -> some View {
        Button { openedID = session.id } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelInk.tertiary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pointingHandCursor { _ in }
        .help(l10n.timelineOpen)
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: VibeTheme.Spacing.s) {
            // Same treatment as `AUTORISATION`: a section label is the panel's way of
            // saying what you are looking at, and there is exactly one colour for «
            // this is VibeBuddy speaking ».
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
