import SwiftUI
import VibeBuddyKit

/// The expanded panel. See RFC-008, "Notes d'implémentation".
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
    var onJump: (pid_t) -> Void = { _ in }
    /// Set only when the last jump has something to say: tab not found,
    /// permission refused.
    var jumpNote: String?
    var pixelSize: Double = Double(BuddyView.defaultPixelSize)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(
                buddy: buddy, expression: expression, sessions: sessions,
                budget: budget, l10n: l10n, pixelSize: pixelSize,
                onSettings: onSettings, onQuit: onQuit
            )

            identityLine

            // Keep this frame: without it the list grows and pushes the header
            // above and the usage below off the panel.
            sessionsSection
                .frame(maxHeight: .infinity, alignment: .top)

            if showUsage {
                Divider().overlay(PanelInk.stroke)
                UsageSection(state: usage, l10n: l10n, locale: locale)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// Who this is, and which build. See RFC-008, "Notes d'implémentation".
    private var identityLine: some View {
        HStack(spacing: 8) {
            Text(AppName.display)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PanelInk.primary)
            Text(AppVersion.short)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(PanelInk.surface))
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
                                onJump: jumpOnClick ? onJump : nil).equatable()
                        }
                    }
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelInk.secondary)
                .tracking(0.8)
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
