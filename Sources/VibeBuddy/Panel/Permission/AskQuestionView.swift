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

    /// Question index → the option under the pointer, whose preview is shown.
    @State private var hovered: [Int: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 10) {
                    promptBlock(question)
                    if !question.options.isEmpty { optionList(question, at: index) }
                    if question.hasPreviews { preview(question, at: index) }
                }
            }
            if questions.contains(where: { !$0.options.isEmpty }) { answerHint }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func promptBlock(_ question: AskedQuestion) -> some View {
        // No ceiling and no scroller of its own: once the panel began sizing itself to
        // its content, a scroller inside a scroller is two things to drag.
        VStack(alignment: .leading, spacing: 4) {
            if let header = question.header {
                VibeBadge(text: header, tint: VibeTheme.Accent.primary)
            }
            Text(question.prompt)
                .font(.system(size: 13))
                .foregroundStyle(PanelInk.primary)
                // Deliberately not `.textSelection(.enabled)`: it installs an I-beam
                // that wins over everything the panel puts on the pointer.
                .fixedSize(horizontal: false, vertical: true)
            if question.multiSelect {
                Text(l10n.permissionPickSeveral)
                    .font(.system(size: 11))
                    .foregroundStyle(PanelInk.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionList(_ question: AskedQuestion, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: VibeTheme.Spacing.xs) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { choice, option in
                let answers = questions.answersOnClick
                QuestionOptionRow(
                    title: option,
                    detail: question.details[choice],
                    // No box to tick when a click answers: a chevron says it goes.
                    symbol: answers ? nil : Self.symbol(multi: question.multiSelect,
                                                        on: selection.isOn(choice, at: index)),
                    isOn: selection.isOn(choice, at: index),
                    onHover: { inside in
                        if inside { hovered[index] = choice }
                        else if hovered[index] == choice { hovered[index] = nil }
                    }
                ) {
                    // The option's own text goes back, so the two sides never have to
                    // agree on an ordering that either could change.
                    if answers { onAnswer([(question.prompt, [option])]) }
                    else { selection.toggle(choice, of: question, at: index) }
                }
            }
        }
    }

    /// The mock-up of the option under the pointer, else of the ticked one, else of the
    /// first. Every preview is laid out and only one is visible: the block takes the
    /// height of the tallest, so hovering never resizes a panel measured once.
    private func preview(_ question: AskedQuestion, at index: Int) -> some View {
        let picked = question.options.indices.first { selection.isOn($0, at: index) }
        let shown = hovered[index] ?? picked
            ?? question.previews.firstIndex { $0 != nil } ?? 0
        return ZStack(alignment: .topLeading) {
            ForEach(Array(question.previews.enumerated()), id: \.offset) { choice, text in
                if let text {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(PanelInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(choice == shown ? 1 : 0)
                }
            }
        }
        .padding(VibeTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
            .fill(VibeTheme.Surface.sunken))
        .overlay(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
            .strokeBorder(VibeTheme.Border.subtle, lineWidth: VibeTheme.Border.width))
    }

    /// Says where a click goes: the user is choosing an answer, not granting a
    /// permission, and this is the one panel where those two are not the same act.
    private var answerHint: some View {
        Text(l10n.permissionAnswerHint)
            .font(.system(size: 11))
            .foregroundStyle(PanelInk.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func symbol(multi: Bool, on: Bool) -> String {
        switch (multi, on) {
        case (true, true): "checkmark.square.fill"
        case (true, false): "square"
        case (false, true): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }
}

/// One option: its label, the line Claude wrote under it, and either a box to tick
/// or a chevron when a click answers outright.
private struct QuestionOptionRow: View {
    let title: String
    let detail: String?
    let symbol: String?
    let isOn: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    @State private var hovering = false

    private var lit: Bool { isOn || hovering }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: VibeTheme.Spacing.s) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(isOn ? VibeTheme.Accent.primary : PanelInk.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VibeTheme.Typography.body)
                        .foregroundStyle(lit ? VibeTheme.Accent.primary : PanelInk.primary)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(PanelInk.tertiary)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if symbol == nil {
                    Image(systemName: hovering ? "arrow.right" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hovering ? VibeTheme.Accent.cyan : PanelInk.tertiary)
                }
            }
            .padding(.horizontal, VibeTheme.Spacing.m)
            .padding(.vertical, VibeTheme.Spacing.s)
            .frame(minHeight: VibeTheme.Control.row)
            .background(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .fill(lit ? VibeTheme.Accent.wash : VibeTheme.Surface.sunken))
            .overlay(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .strokeBorder(lit ? VibeTheme.Accent.border : VibeTheme.Border.subtle,
                              lineWidth: VibeTheme.Border.width))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium))
        .pointingHandCursor {
            hovering = $0
            onHover($0)
        }
    }
}
