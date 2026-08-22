import SwiftUI

/// A small word in a capsule: a state, an effort, a permission mode, a count.
///
/// There were four of these, each with its own background: the state chip at
/// `colour.opacity(0.16)`, the effort badge at `0.18` or `PanelInk.stroke`, and
/// two more at `PanelInk.stroke`. Three values for one idea, and the loudest of
/// them competed with the session's own name — which section 17 of the brief
/// names as the thing a badge must never do.
///
/// **The fill is darker than what it replaced, on purpose.** A tinted wash at
/// 0.16 over black reads as a coloured pill; at 0.10 it reads as the word
/// glowing slightly against the panel. The colour belongs to the text, and the
/// background's whole job is to give it an edge to sit in.
struct VibeBadge: View {
    let text: String
    /// The word's colour. Nil for the ones that carry no state — a permission
    /// mode, a run count — which stay in the ink scale.
    var tint: Color?
    var monospaced = false

    var body: some View {
        Text(text)
            .font(monospaced
                  ? VibeTheme.Typography.mono(10, weight: .medium)
                  : .system(size: 10, weight: .semibold))
            .foregroundStyle(tint ?? PanelInk.secondary)
            .padding(.horizontal, VibeTheme.Spacing.s)
            .padding(.vertical, VibeTheme.Spacing.xxs)
            .background(Capsule().fill(fill))
            .fixedSize()
    }

    private var fill: Color {
        // A tinted badge sits in its own colour, a neutral one in the panel's
        // sunken surface. Both land in the same range of lightness, which is
        // what keeps a row of badges looking like a row rather than a ladder.
        tint.map { $0.opacity(0.10) } ?? VibeTheme.Surface.sunken
    }
}
