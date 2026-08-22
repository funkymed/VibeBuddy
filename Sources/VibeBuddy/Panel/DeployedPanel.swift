import SwiftUI
import VibeBuddyKit

/// The expanded panel: what every deployed state shares, and whatever that
/// state puts under it.
///
/// **The header belongs to the panel, not to one of its contents.** It used to
/// live inside `PanelContentView`, so opening a permission replaced it with a
/// header of the permission's own — the buddy stayed, the counter, the settings
/// gear and the quit button did not. Deploying the notch and being asked for a
/// permission are the same window in the same state; losing the controls on the
/// way in makes it read as a different one. The identity line moved up for the
/// same reason, and matters most exactly there: a panel that appears on its own
/// asking to run `rm -rf` should say who is asking.
///
/// It also gives the offscreen measurement in `NotchPanel` something exact to
/// measure: the same wrapper the screen draws, not an approximation of it plus
/// a guessed header height.
struct DeployedPanel<Content: View>: View {
    let header: PanelHeader
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            identityLine
            // Under the identity, not under the header: it closes « who is
            // asking » and opens whatever this state has to say. Without it the
            // name and the content read as one block.
            VibeDivider()
            content()
        }
        .padding(.horizontal, PanelMetrics.contentInset.width)
        .padding(.top, PanelMetrics.contentInset.height)
        .padding(.bottom, 12)
    }

    /// Who this is, and which build. See RFC-008, « Notes d'implémentation ».
    private var identityLine: some View {
        HStack(spacing: VibeTheme.Spacing.s) {
            Text(AppName.display)
                .font(VibeTheme.Typography.cardTitle)
                .foregroundStyle(PanelInk.primary)
            // The version in the accent, and the accent nowhere else on this
            // row: it is the one piece of it anybody ever needs to read twice.
            Spacer(minLength: VibeTheme.Spacing.s)
            // Pushed to the far edge rather than tucked against the name: the
            // row then has one thing at each end, like the header above it,
            // instead of a pair floating in a wide empty block.
            Text(AppVersion.short)
                .font(VibeTheme.Typography.mono(12, weight: .medium))
                .foregroundStyle(VibeTheme.Accent.primary)
        }
        .padding(.horizontal, VibeTheme.Spacing.m)
        // Measured off the reference: that block is 40 px tall on a 503 px
        // render of a 560 pt panel — about 44 pt, where ours was 30. Section 10
        // of the brief asks for « padding généreux » and this is what the number
        // turns out to be.
        .padding(.vertical, VibeTheme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .fill(VibeTheme.Surface.sunken))
        .overlay(
            RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .strokeBorder(VibeTheme.Border.subtle, lineWidth: VibeTheme.Border.width))
    }
}
