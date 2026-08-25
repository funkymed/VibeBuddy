import SwiftUI
import VibeBuddyKit

/// The row of live faces, one per declared expression, doubling as a selector.
struct BuddyPreviewStrip: View {
    /// The default for every face in the strip: no clock at all.
    @MainActor static let still = AnimationBudget()

    /// The clock the clicked face borrows, and only it.
    @MainActor static let lively: AnimationBudget = {
        let budget = AnimationBudget()
        budget.set(.lively)
        return budget
    }()

    /// How long a face keeps moving after a click.
    private static let animationDuration: Duration = .seconds(6)

    let manifest: BuddyManifest
    let expressions: [BuddyExpression]
    @Binding var selection: BuddyExpression

    /// The face currently moving, if any.
    @State private var animating: BuddyExpression?

    /// Bumped by every click, including a click on the face already moving.
    @State private var runs = 0

    var body: some View {
        HStack(spacing: 18) {
            ForEach(expressions, id: \.self) { expression in
                // Selecting and animating are the same click: you press a face to
                // choose it, and seeing it move is how you judge the choice.
                Button {
                    selection = expression
                    animating = expression
                    runs += 1
                } label: {
                    BuddyView(
                        manifest: manifest, expression: expression,
                        budget: expression == animating ? Self.lively : Self.still)
                        .fixedSize()
                        .opacity(expression == selection ? 1 : 0.45)
                        // Required. `BuddyView` ends on `.allowsHitTesting(false)`
                        // — it is a drawing, and in the notch it must never intercept a
                        // click meant for the panel underneath.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityLabel(Text(expression.rawValue))
            }
        }
        // Restarted by each click, cancelled when the window goes away: a `.task(id:)`
        // is torn down with the view, where a timer would have to be remembered and
        // stopped by hand (decision D3 — one clock, and this is not it).
        .task(id: runs) {
            guard animating != nil else { return }
            try? await Task.sleep(for: Self.animationDuration)
            guard !Task.isCancelled else { return }
            animating = nil
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black))
    }
}
