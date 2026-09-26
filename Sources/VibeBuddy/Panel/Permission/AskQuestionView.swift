import SwiftUI
import VibeBuddyKit

/// The agent is waiting on a person: `AskUserQuestion`, or `ExitPlanMode`.
struct AskQuestionView: View {
    let questions: [AskedQuestion]
    let l10n: Strings
    /// Each question with its picks, as the options' own text — never an index.
    var onAnswer: (QuestionPicks) -> Void

    /// What is ticked. Held by the panel, whose decision bar carries « Envoyer ».
    @Binding var selection: QuestionSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 10) {
                    promptBlock(question)
                    if !question.options.isEmpty { optionList(question, at: index) }
                }
            }
            if questions.contains(where: { !$0.options.isEmpty }) { answerHint }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promptBlock(_ question: AskedQuestion) -> some View {
        // No ceiling and no scroller of its own. It had both, and they were wrong
        // twice over: the frame was a floor as much as a cap, so a one-line question
        // reserved 140 pt of black; and once the panel began sizing itself to its
        // content, a scroller inside a scroller is two things to drag.
        VStack(alignment: .leading, spacing: 2) {
            Text(question.prompt)
                .font(.system(size: 13))
                .foregroundStyle(PanelInk.primary)
                // Deliberately not `.textSelection(.enabled)`: it installs an I-beam
                // that wins over everything the panel puts on the pointer, so the hand
                // flickered on every button and row.
                .fixedSize(horizontal: false, vertical: true)
            if question.multiSelect {
                Text(l10n.permissionPickSeveral)
                    .font(.system(size: 11))
                    .foregroundStyle(PanelInk.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func optionList(_ question: AskedQuestion, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: VibeTheme.Spacing.xs) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { choice, option in
                if questions.answersOnClick {
                    // The option's own text is what goes back, so the two sides never
                    // have to agree on an ordering that either could change.
                    VibeButton(title: option, role: .neutral, isRow: true) {
                        onAnswer([(question.prompt, [option])])
                    }
                } else {
                    QuestionOptionRow(
                        title: option, isMulti: question.multiSelect,
                        isOn: selection.isOn(choice, at: index)
                    ) { selection.toggle(choice, of: question, at: index) }
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

/// An option that is picked, not sent: a checkbox for several, a radio for one.
private struct QuestionOptionRow: View {
    let title: String
    let isMulti: Bool
    let isOn: Bool
    let action: () -> Void

    private var symbol: String {
        switch (isMulti, isOn) {
        case (true, true): "checkmark.square.fill"
        case (true, false): "square"
        case (false, true): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VibeTheme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? VibeTheme.Accent.primary : PanelInk.tertiary)
                Text(title)
                    .font(VibeTheme.Typography.body)
                    .foregroundStyle(isOn ? VibeTheme.Accent.primary : PanelInk.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, VibeTheme.Spacing.m)
            .frame(minHeight: VibeTheme.Control.row)
            .background(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .fill(isOn ? VibeTheme.Accent.wash : VibeTheme.Surface.sunken))
            .overlay(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .strokeBorder(isOn ? VibeTheme.Accent.border : VibeTheme.Border.subtle,
                              lineWidth: VibeTheme.Border.width))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium))
        .pointingHandCursor()
    }
}
