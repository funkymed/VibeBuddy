import SwiftUI
import VibeBuddyKit

/// Context used: a ring and the number. The ring alone is ambiguous — the
/// window is either 200k or 1M, and which one changes what half means.
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

    private var gaugeColour: Color {
        switch session.contextFraction {
        case ..<0.7: return PanelInk.secondary
        case ..<0.9: return .orange
        default:     return .red
        }
    }
}
