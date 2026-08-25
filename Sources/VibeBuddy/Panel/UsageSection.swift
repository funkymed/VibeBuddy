import SwiftUI
import VibeBuddyKit

/// The two limit windows, at the foot of the panel.
struct UsageSection: View {
    let state: UsageState.Status
    let l10n: Strings
    let locale: Locale

    private var age: TimeInterval? {
        guard case let .ready(usage) = state else { return nil }
        return Date().timeIntervalSince(usage.fetchedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(l10n.usageTitle)
                    .font(VibeTheme.Typography.section)
                    .foregroundStyle(VibeTheme.Accent.primary)
                    .tracking(VibeTheme.Typography.sectionTracking)
                if case let .unavailable(reason) = state {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                // Said only once it matters: the endpoint refuses far more often than
                // it answers, so a stale reading is worth flagging.
                if let age, age > 120, case let .ready(usage) = state {
                    Text(l10n.usageAge(SessionRow.duration(since: usage.fetchedAt)))
                        .font(.system(size: 11))
                        .foregroundStyle(PanelInk.tertiary)
                }
            }

            switch state {
            case .unknown:
                Text(l10n.usageLoading)
                    .font(.system(size: 13))
                    .foregroundStyle(PanelInk.tertiary)
            case let .ready(usage):
                UsageBar(label: l10n.usageSession, window: usage.fiveHour, locale: locale)
                UsageBar(label: l10n.usageWeek, window: usage.sevenDay, locale: locale)
            case .unavailable:
                // Empty gauges rather than nothing, and never a zero — a zero would
                // read as good news.
                UsageBar(label: l10n.usageSession, window: nil, locale: locale)
                UsageBar(label: l10n.usageWeek, window: nil, locale: locale)
            }
        }
    }
}
