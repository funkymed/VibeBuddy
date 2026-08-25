import SwiftUI
import VibeBuddyKit

/// One limit window: a label, a dotted gauge, a percentage, a reset time.
struct UsageBar: View {
    let label: String
    let window: ClaudeUsage.Window?
    let locale: Locale
    var dotCount: Int = 10

    /// Rounded up: rounding down renders 4 % as an empty gauge, which reads as "not
    /// started" rather than "barely started".
    private var filled: Int {
        guard let window, window.utilisation > 0 else { return 0 }
        return max(1, Int((window.fraction * Double(dotCount)).rounded(.up)))
    }

    /// The shared quota scale — see `QuotaScale`, which the per-session context ring
    /// reads from too.
    private var tint: Color {
        guard let window else { return QuotaScale.unknown }
        return QuotaScale.colour(window.fraction)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(PanelInk.secondary)
                .frame(width: 68, alignment: .leading)

            // 9 pt dots, not 6: a 6 pt ring with a 1 pt border leaves 4 pt of fill, the
            // smallest thing on a Retina panel and unusable to count.
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
                .foregroundStyle(window == nil ? PanelInk.tertiary : tint)
                .contentTransition(.numericText())
                .frame(width: 42, alignment: .trailing)

            if let resets = window?.resetsAt {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                    Text(Self.resetText(resets, locale: locale))
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(PanelInk.tertiary)
            }

            Spacer(minLength: 0)
        }
    }

    private var percentText: String {
        guard let window else { return "—" }
        return "\(Int(window.utilisation.rounded()))%"
    }

    /// A time for today, a date beyond: "22:20" against "23 août, 20:00".
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
