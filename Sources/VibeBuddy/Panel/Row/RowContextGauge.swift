import SwiftUI
import VibeBuddyKit

/// Context used: a ring and the number.
struct RowContextGauge: View {
    let session: AgentSession
    let l10n: Strings

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(PanelInk.stroke, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: session.contextFraction)
                    .stroke(gaugeColour, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 17, height: 17)
            Text("\(Int((session.contextFraction * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())
                .foregroundStyle(gaugeColour)
        }
        .help(l10n.contextTooltip(session.contextTokens, session.contextWindow))
    }

    /// The same scale as the consumption meter in the footer — `QuotaScale`. It used to
    /// stay grey below 70 %, which made a session at 60 % look like one at 3 %: the ring
    /// was drawn and said nothing.
    private var gaugeColour: Color {
        QuotaScale.colour(session.contextFraction)
    }
}
