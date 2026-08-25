import SwiftUI

/// A small word in a capsule: a state, an effort, a permission mode, a count.
struct VibeBadge: View {
    let text: String
    /// The word's colour.
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
        // A tinted badge sits in its own colour, a neutral one in the panel's sunken
        // surface.
        tint.map { $0.opacity(0.10) } ?? VibeTheme.Surface.sunken
    }
}
