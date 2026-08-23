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
        // **No ceiling and no scroller of its own.** It had both, and they were
        // wrong twice over: the frame was a floor as much as a cap, so a
        // one-line question reserved 140 pt of black; and once the panel began
        // sizing itself to its content, a scroller inside a scroller is two
        // things to drag. The whole summary scrolls, once, in
        // `PermissionPanelView` — the header and the decision bar stay put.
        Text(prompt)
            .font(.system(size: 13))
            .foregroundStyle(PanelInk.primary)
            // Deliberately **not** `.textSelection(.enabled)`: it installs an I-beam
            // that wins over everything the panel puts on the pointer, so the hand
            // flickered on every button and row. A panel whose cursor cannot be trusted
            // is worse than one you cannot copy out of — and the text here is already
            // cut at parse time, so it was never the place to read a plan from anyway.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The answers

    private var optionList: some View {
        VStack(alignment: .leading, spacing: VibeTheme.Spacing.xs) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                // The option's own text is what goes back, so the two sides
                // never have to agree on an ordering that either could change.
                // No index, no shared state: the button lights from its own
                // pointer, which is the only place a pointer can be.
                VibeButton(title: option, role: .neutral, isRow: true) {
                    onAnswer(option)
                }
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
