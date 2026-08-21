import SwiftUI
import VibeBuddyKit

/// The agent is waiting on a person: `AskUserQuestion`, or `ExitPlanMode`.
///
/// There is no "answer" in the hook protocol — allow or deny, nothing else. The
/// chosen option travels back through `onAnswer`, which the panel's owner sends
/// as a `deny` whose message is `denyMessage(for:)`; the model reads it as a
/// tool result and carries on. See RFC-007 §1 and §3.
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
    private static let planHeight: CGFloat = 260
    private static let questionHeight: CGFloat = 140

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
        }
        .frame(maxHeight: options.isEmpty ? Self.planHeight : Self.questionHeight)
        .scrollBounceBehavior(.basedOnSize)
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

    // MARK: - The hijack

    /// The message a chosen option is sent back as — a **deny** whose reason is
    /// phrased as the answer.
    ///
    /// This is a hijack, and it is deliberate. The hook can only allow or deny
    /// a tool; there is no channel to hand it an answer with (RFC-007 §1, and
    /// §4 records that allowing plus an out-of-band reply was looked for and
    /// does not exist). Denying `AskUserQuestion` with the chosen option as the
    /// reason works because the model reads a deny reason as the tool's result
    /// and keeps going. Anyone who "fixes" this into an `allow` breaks every
    /// question the user answers from the notch.
    ///
    /// English on purpose: the model reads this string, the user never sees it,
    /// so it stays out of `Strings` and does not follow the UI language.
    static func denyMessage(for option: String) -> String {
        "The user chose: \"\(option)\". "
            + "This is the answer to your question, not a refusal — continue with it."
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
