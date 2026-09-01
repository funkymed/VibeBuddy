import SwiftUI
import VibeBuddyKit

/// The expanded panel: what every deployed state shares, and whatever that state puts
/// under it.
struct DeployedPanel<Content: View>: View {
    let header: PanelHeader
    /// The newer version, when one exists. Nil almost always.
    var updateAvailable: String?
    var l10n: Strings = .french
    var onUpdate: () -> Void = {}
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            identityLine
            // Under the identity, not under the header: it closes « who is asking » and
            // opens whatever this state has to say.
            VibeDivider()
            content()
        }
        .padding(.horizontal, PanelMetrics.contentInset.width)
        .padding(.top, PanelMetrics.contentInset.height)
        .padding(.bottom, 12)
    }

    /// Who this is, and which build.
    private var identityLine: some View {
        HStack(spacing: VibeTheme.Spacing.s) {
            Text(AppName.display)
                .font(VibeTheme.Typography.cardTitle)
                .foregroundStyle(PanelInk.primary)
            // The version in the accent, and the accent nowhere else on this row: it is
            // the one piece of it anybody ever needs to read twice.
            Spacer(minLength: VibeTheme.Spacing.s)
            // Pushed to the far edge rather than tucked against the name: the row then
            // has one thing at each end, like the header above it, instead of a pair
            // floating in a wide empty block.
            // Beside the version, because that is the number it is about. The header
            // row above sits at the height of the physical notch, where a chip is
            // behind the hardware and unreadable.
            if let updateAvailable { updateChip(updateAvailable) }
            Text(AppVersion.short)
                .font(VibeTheme.Typography.mono(12, weight: .medium))
                .foregroundStyle(VibeTheme.Accent.primary)
        }
        .padding(.horizontal, VibeTheme.Spacing.m)
        // Measured off the reference: that block is 40 px tall on a 503 px render of a
        // 560 pt panel — about 44 pt, where ours was 30.
        .padding(.vertical, VibeTheme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .fill(VibeTheme.Surface.sunken))
        .overlay(
            RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                .strokeBorder(VibeTheme.Border.subtle, lineWidth: VibeTheme.Border.width))
    }

    /// Where a new version gets noticed inside the panel. The settings say it properly;
    /// this is the line somebody already reads to know which build they are on.
    private func updateChip(_ version: String) -> some View {
        Button(action: onUpdate) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(l10n.updateBadge(version))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(VibeTheme.Accent.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(VibeTheme.Accent.wash))
            .overlay(Capsule().strokeBorder(VibeTheme.Accent.border,
                                            lineWidth: VibeTheme.Border.width))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help(l10n.updateBadge(version))
        .pointingHandCursor()
    }
}
