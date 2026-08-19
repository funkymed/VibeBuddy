import SwiftUI
import NotchBuddyKit

/// One limit window: a label, a dotted gauge, a percentage, a reset time.
///
/// Dots rather than a continuous bar. At this width a bar's fill is a few
/// pixels of difference between 15 % and 25 %, where a filled dot is countable
/// at a glance — the reading is "two out of ten", not "about a fifth".
struct UsageBar: View {
    let label: String
    let window: ClaudeUsage.Window?
    let locale: Locale
    var dotCount: Int = 10

    /// Dots filled, rounded up so any usage at all shows at least one.
    ///
    /// Rounding down would render 4 % as an empty gauge, which reads as "not
    /// started" rather than "barely started".
    private var filled: Int {
        guard let window, window.utilisation > 0 else { return 0 }
        return max(1, Int((window.fraction * Double(dotCount)).rounded(.up)))
    }

    private var tint: Color {
        guard let window else { return .white.opacity(0.25) }
        switch window.fraction {
        case ..<0.7:  return .green
        case ..<0.9:  return .orange
        default:      return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 68, alignment: .leading)

            // Nine points, not six. A 6 pt ring with a 1 pt border leaves four
            // points of fill: on a Retina panel that is the smallest thing on
            // screen, and counting ten of them was the one thing this gauge is
            // for. The border thickens with the dot so an empty one still reads
            // as a dot rather than as a smudge.
            HStack(spacing: 3) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
                        .background(Circle().fill(index < filled ? tint : .clear))
                        .frame(width: 9, height: 9)
                }
            }

            Text(percentText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(window == nil ? .white.opacity(0.35) : tint)
                .frame(width: 42, alignment: .trailing)

            if let resets = window?.resetsAt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text(Self.resetText(resets, locale: locale))
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)
        }
    }

    private var percentText: String {
        guard let window else { return "—" }
        return "\(Int(window.utilisation.rounded()))%"
    }

    /// A time for today, a date for anything later.
    ///
    /// "22:20" is unambiguous when it is a few hours away; "23 août 20:00" is
    /// what a weekly reset needs. Showing a full date for a reset two hours out
    /// makes the reader do arithmetic.
    static func resetText(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "d MMM, HH:mm"
        }
        return formatter.string(from: date)
    }
}

/// The two limit windows, at the foot of the panel.
struct UsageSection: View {
    let state: UsageState.Status
    let l10n: Strings
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(l10n.usageTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.8)
                if case let .unavailable(reason) = state {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }

            switch state {
            case .unknown:
                Text(l10n.usageLoading)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
            case let .ready(usage):
                UsageBar(label: l10n.usageSession, window: usage.fiveHour, locale: locale)
                UsageBar(label: l10n.usageWeek, window: usage.sevenDay, locale: locale)
            case .unavailable:
                // Empty gauges rather than nothing, so the section keeps its
                // shape — and never a zero, which would read as good news.
                UsageBar(label: l10n.usageSession, window: nil, locale: locale)
                UsageBar(label: l10n.usageWeek, window: nil, locale: locale)
            }
        }
    }
}


/// Reset formatting, reachable from diagnostics without building a view.
enum UsageBarPreview {
    static func reset(_ date: Date) -> String { UsageBar.resetText(date) }
}
