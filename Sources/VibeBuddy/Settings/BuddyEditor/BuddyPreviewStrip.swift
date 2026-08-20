import SwiftUI
import VibeBuddyKit

/// The row of live faces, one per declared expression, doubling as a selector.
///
/// See RFC-010, "Notes d'implémentation".
struct BuddyPreviewStrip: View {
    let manifest: BuddyManifest
    let expressions: [BuddyExpression]
    let pixelSize: Double
    @Binding var selection: BuddyExpression

    var body: some View {
        HStack(spacing: 18) {
            ForEach(expressions, id: \.self) { expression in
                Button { selection = expression } label: {
                    BuddyView(
                        manifest: manifest, expression: expression,
                        budget: BuddyEditorBudget.shared, pixelSize: pixelSize)
                        .fixedSize()
                        .opacity(expression == selection ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityLabel(Text(expression.rawValue))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black))
    }
}
