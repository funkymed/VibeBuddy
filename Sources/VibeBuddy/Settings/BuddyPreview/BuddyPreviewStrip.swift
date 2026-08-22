import SwiftUI
import VibeBuddyKit

/// The row of live faces, one per declared expression, doubling as a selector.
///
/// See RFC-010, "Notes d'implémentation".
struct BuddyPreviewStrip: View {

    /// The default for every face in the strip: no clock at all.
    ///
    /// A settings window is not a place to spend one — six faces at thirty
    /// frames a second, to look at one. The exception is the face you just
    /// clicked; see `lively`.
    @MainActor static let still = AnimationBudget()

    /// The clock the clicked face borrows, and only it.
    ///
    /// Held as a second budget rather than by flipping `still`: they are read
    /// by different views at the same moment — one face moving, the others
    /// static — and a single shared budget cannot say both.
    @MainActor static let lively: AnimationBudget = {
        let budget = AnimationBudget()
        budget.set(.lively)
        return budget
    }()

    /// How long a face keeps moving after a click.
    ///
    /// Long enough to see a blink, a look around and a return — the sequence is
    /// built on beats of one to two seconds. Bounded because nothing here is
    /// worth an animation that outlives the reason it started: a settings
    /// window left open on a desk would otherwise draw at thirty frames a
    /// second until it is closed.
    private static let animationDuration: Duration = .seconds(6)

    let manifest: BuddyManifest
    let expressions: [BuddyExpression]
    @Binding var selection: BuddyExpression

    /// The face currently moving, if any. **At most one**, by construction:
    /// clicking another overwrites it, and the one that loses the slot is
    /// handed `still` on the very next redraw, which stops its clock.
    @State private var animating: BuddyExpression?

    /// Bumped by every click, including a click on the face already moving.
    ///
    /// The countdown keys on this rather than on the expression: keyed on the
    /// expression, clicking the same face twice changes nothing, so `.task`
    /// keeps its first deadline and the animation dies at six seconds after the
    /// *first* click — which reads as a buddy that ignores you.
    @State private var runs = 0

    var body: some View {
        HStack(spacing: 18) {
            ForEach(expressions, id: \.self) { expression in
                // Selecting and animating are the same click: you press a face
                // to choose it, and seeing it move is how you judge the choice.
                // A still portrait tells you the colour and nothing else — this
                // buddy's whole character is in its timing.
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
                        // **Required.** `BuddyView` ends on
                        // `.allowsHitTesting(false)` — it is a drawing, and in
                        // the notch it must never intercept a click meant for
                        // the panel underneath. As a button's label that makes
                        // the button unclickable: the face covers it entirely
                        // and refuses every hit, so nothing happened here at
                        // all. A `contentShape` on the wrapper gives the button
                        // back a hit area of its own without the face taking
                        // any.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityLabel(Text(expression.rawValue))
            }
        }
        // Restarted by each click, cancelled when the window goes away: a
        // `.task(id:)` is torn down with the view, where a timer would have to
        // be remembered and stopped by hand (decision D3 — one clock, and this
        // is not it).
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
