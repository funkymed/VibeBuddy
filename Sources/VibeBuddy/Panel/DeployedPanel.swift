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
            Divider().overlay(PanelInk.stroke)
            content()
        }
        .padding(.horizontal, PanelMetrics.contentInset.width)
        .padding(.top, PanelMetrics.contentInset.height)
        .padding(.bottom, 12)
    }

    /// Who this is, and which build. See RFC-008, « Notes d'implémentation ».
    private var identityLine: some View {
        HStack(spacing: 8) {
            Text(AppName.display)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PanelInk.primary)
            Text(AppVersion.short)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(PanelInk.surface))
    }
}
