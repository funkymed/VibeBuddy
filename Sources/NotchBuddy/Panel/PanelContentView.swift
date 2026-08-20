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
    /// Clicking a live row goes back to its terminal. The work happens in
    /// `AppCoordinator`, which owns side effects; the view only reports.
    var onJump: (pid_t) -> Void = { _ in }
    /// Result of the last jump, when it is worth saying — a tab that could not
    /// be found, or a refused permission. Nil the rest of the time, because a
    /// jump that worked is its own confirmation: the terminal is now in front.
    var jumpNote: String?
    var pixelSize: Double = Double(BuddyView.defaultPixelSize)
    /// One row per directory rather than one per transcript.
    var groupByDirectory = true
    var jumpOnClick = true
    var showUsage = true


    private var visible: [SessionGroup] {
        // Ungrouped is not "no grouping applied" — it is one group per session,
        // so the row keeps working without a second code path for its badges.
        groupByDirectory
            ? SessionGroup.group(sessions)
            : SessionGroup.ungrouped(sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(
                buddy: buddy, expression: expression, sessions: sessions,
                budget: budget, l10n: l10n, pixelSize: pixelSize,
                onSettings: onSettings, onQuit: onQuit
            )

            identityLine

            // The list scrolls; the header above and the usage below do not.
            //
            // Without this the list simply grew and pushed both off the panel —
            // an afternoon of runs in one directory was enough to lose the very
            // readings the panel exists for.
            sessionsSection
                .frame(maxHeight: .infinity, alignment: .top)

            if showUsage {
                Divider().overlay(.white.opacity(0.08))
                UsageSection(state: usage, l10n: l10n, locale: locale)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Who this is, and which build.
    ///
    /// This replaces the filter field that used to sit here. Grouping by
    /// directory removed the clutter the filter existed to cut through — six
    /// rows of one project became one — so a search box over three or four rows
    /// was furniture standing in for a feature.
    ///
    /// The version earns its place: buddies and settings are files on disk that
    /// outlive a build, and knowing which build is reading them is the first
    /// thing anyone needs when one behaves oddly.
    private var identityLine: some View {
        HStack(spacing: 7) {
            Text("notch-buddy")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(AppVersion.short)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
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
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        // Already ordered live-first, then by recency —
                        // `SessionGroup.group` owns that rule so the view and
                        // the tests cannot disagree about it.
                        ForEach(visible) { group in
                            SessionRow(
                                group: group, l10n: l10n,
                                onJump: jumpOnClick ? onJump : nil).equatable()
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(0.8)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.32))
        }
    }

    private var emptyState: some View {
        Text(l10n.emptyHint)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.vertical, 10)
    }

}
