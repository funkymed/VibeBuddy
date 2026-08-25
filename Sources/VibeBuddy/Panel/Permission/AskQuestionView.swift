import SwiftUI
import VibeBuddyKit

/// The agent is waiting on a person: `AskUserQuestion`, or `ExitPlanMode`.
struct AskQuestionView: View {
    let prompt: String
    let options: [String]
    let l10n: Strings
    /// The option's text exactly as it was offered — never an index.
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

    private var promptBlock: some View {
        // No ceiling and no scroller of its own. It had both, and they were wrong
        // twice over: the frame was a floor as much as a cap, so a one-line question
        // reserved 140 pt of black; and once the panel began sizing itself to its
        // content, a scroller inside a scroller is two things to drag.
        Text(prompt)
            .font(.system(size: 13))
            .foregroundStyle(PanelInk.primary)
            // Deliberately not `.textSelection(.enabled)`: it installs an I-beam
            // that wins over everything the panel puts on the pointer, so the hand
            // flickered on every button and row.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionList: some View {
        VStack(alignment: .leading, spacing: VibeTheme.Spacing.xs) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                // The option's own text is what goes back, so the two sides never have
                // to agree on an ordering that either could change.
                VibeButton(title: option, role: .neutral, isRow: true) {
                    onAnswer(option)
                }
            }
        }
    }

    /// Says where a click goes, because the button says nothing about it: the user is
    /// choosing an answer, not granting a permission, and this is the one panel where
    /// those two are not the same act.
    private var answerHint: some View {
        Text(l10n.permissionAnswerHint)
            .font(.system(size: 11))
            .foregroundStyle(PanelInk.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
