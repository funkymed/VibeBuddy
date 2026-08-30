import SwiftUI
import VibeBuddyKit

/// Asks before a row leaves the list.
///
/// A dialog for something reversible looks like ceremony, and it is: the click sits two
/// pixels from the one that jumps to the terminal, and a row that vanishes without a
/// word reads as a bug rather than as an action.
struct SessionDismissDialog: View {
    let session: AgentSession
    let l10n: Strings
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            // Swallows the clicks the list would otherwise still take: the rows behind
            // stay readable, which is the point of a dialog over a replacement screen,
            // but they stop being live targets.
            Rectangle()
                .fill(.black.opacity(0.55))
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            card
                .padding(.horizontal, VibeTheme.Spacing.l)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.dismissTitle)
                .font(VibeTheme.Typography.section)
                .foregroundStyle(VibeTheme.Accent.primary)
                .tracking(VibeTheme.Typography.sectionTracking)

            Text(l10n.dismissBody(session.projectName))
                .font(.system(size: 12))
                .foregroundStyle(PanelInk.primary)
                .fixedSize(horizontal: false, vertical: true)

            // The sentence that makes this safe to click, said where it is read.
            Text(l10n.dismissKeepsTranscript)
                .font(.system(size: 10))
                .foregroundStyle(PanelInk.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: VibeTheme.Spacing.s) {
                Spacer(minLength: 0)
                VibeButton(title: l10n.dismissCancel, role: .neutral, action: onCancel)
                VibeButton(title: l10n.dismissConfirm, role: .accent, action: onConfirm)
            }
        }
        .padding(VibeTheme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
            .fill(VibeTheme.Surface.raised))
        .overlay(RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
            .strokeBorder(VibeTheme.Border.strong, lineWidth: VibeTheme.Border.width))
    }
}
