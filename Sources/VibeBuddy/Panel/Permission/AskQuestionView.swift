import SwiftUI
import VibeBuddyKit

/// The agent is waiting on a person: `AskUserQuestion`, or `ExitPlanMode`.
///
/// There is no "answer" in the hook protocol — allow or deny, nothing else. The
/// chosen option travels back through `onAnswer`, which the panel's owner sends
/// as a `deny` whose message is `QuestionAnswer.denyMessage(for:)`; the model
/// reads it as a tool result and carries on. See RFC-007 §1 and §3.
///
/// The hijack's wording lives in the Kit, not here: this view offers the
/// options, it is not what sends them back.
///
/// A question with no options is `ExitPlanMode`, whose prompt is the plan
/// itself: it shows the plan and nothing more, because the panel's own
/// Deny / Allow bar already says the two things there are to say about a plan.
// RFC-007 T6
struct AskQuestionView: View {
    let prompt: String
    let options: [String]
    let l10n: Strings
    /// The option's text exactly as it was offered — never an index. The list
    /// the hook sent is the only thing both sides agree on.
    var onAnswer: (String) -> Void

    /// A plan gets the room a plan needs; a question shares its space with the
    /// buttons underneath it. Past either, the block scrolls — the text was
    /// already cut at parse time, so neither is ever unbounded.
    ///
    /// **A ceiling, and only a ceiling.** `ScrollView` takes whatever height it
    /// is allowed, so `frame(maxHeight:)` alone was a floor too: a one-line
    /// question reserved the full 140 pt and left about 120 pt of black between
    /// itself and the first option — seen on screen 2026-08-22, and worse on a
    /// plan at 260. The text is measured and the block takes the smaller of the
    /// two.
    private static let planHeight: CGFloat = 260
    private static let questionHeight: CGFloat = 140

    /// The prompt's own height, once laid out at the panel's width.
    ///
    /// Starts at the ceiling rather than at zero: the first frame is drawn
    /// before any measurement comes back, and growing into place is a movement
    /// the panel is not allowed to make. Too much room for one frame is
    /// invisible; too little clips the text.
    @State private var measuredPrompt: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            promptBlock

            if !options.isEmpty {
                optionList
                answerHint
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The ask

    private var promptBlock: some View {
        ScrollView(.vertical) {
            Text(prompt)
                .font(.system(size: 13))
                .foregroundStyle(PanelInk.primary)
                // A plan is worth copying out of the notch and into a note.
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Measured where the text is laid out, not where it is shown:
                // the width comes from the panel and does not depend on the
                // height we hand back, so this settles in one pass instead of
                // chasing itself.
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PromptHeightKey.self, value: proxy.size.height)
                    })
        }
        .frame(height: min(measuredPrompt ?? ceiling, ceiling))
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(PromptHeightKey.self) { height in
            // `nil` until the first real measurement: a zero arriving before
            // layout would collapse the block and then push it open again.
            if height > 0 { measuredPrompt = height }
        }
    }

    /// How much room this prompt may take at most.
    private var ceiling: CGFloat {
        options.isEmpty ? Self.planHeight : Self.questionHeight
    }

    // MARK: - The answers

    private var optionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                // The option's own text is what goes back, so the two sides
                // never have to agree on an ordering that either could change.
                AskOptionButton(title: option) { onAnswer(option) }
            }
        }
    }

    /// Says where a click goes, because the button says nothing about it: the
    /// user is choosing an answer, not granting a permission, and this is the
    /// one panel where those two are not the same act.
    private var answerHint: some View {
        Text(l10n.permissionAnswerHint)
            .font(.system(size: 11))
            .foregroundStyle(PanelInk.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The prompt's laid-out height, passed from inside the scroller to the frame
/// around it.
private struct PromptHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One option, drawn as a full-width target.
///
/// Its own view for its own hover state: hovering one option must not redraw
/// the others, and a `@State` per button is what keeps that local.
private struct AskOptionButton: View {
    let title: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(PanelInk.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Hover swaps a fill; it is not animated. RFC-007 §2 forbids
            // anything that keeps drawing while the user thinks.
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? PanelInk.stroke : PanelInk.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PanelInk.stroke))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .pointingHandCursor { hovering = $0 }
    }
}
