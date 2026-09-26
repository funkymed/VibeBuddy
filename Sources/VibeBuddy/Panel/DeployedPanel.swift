import SwiftUI
import VibeBuddyKit

/// The expanded panel: what every deployed state shares, and whatever that state puts
/// under it.
struct DeployedPanel<Content: View>: View {
    let header: PanelHeader
    /// Empty almost always.
    var notices = PanelNotices()
    var l10n: Strings = .french
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
            if notices.hookMissing {
                PanelNoticeChip(symbol: "exclamationmark.triangle", text: l10n.hookNotice,
                                help: l10n.hookNoticeHint, action: notices.onHookNotice)
            }
            if let version = notices.updateAvailable {
                PanelNoticeChip(symbol: "arrow.down.circle", text: l10n.updateBadge(version),
                                help: l10n.updateBadge(version), action: notices.onUpdate)
            }
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
}

/// What the identity line can carry besides the version.
struct PanelNotices {
    /// The newer version, when one exists.
    var updateAvailable: String?
    var onUpdate: () -> Void = {}
    var hookMissing = false
    var onHookNotice: () -> Void = {}
}

/// Where a notice gets seen inside the panel: on the line somebody already reads to
/// know which build they are on. The settings say it properly.
struct PanelNoticeChip: View {
    let symbol: String
    let text: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(text)
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
        .help(help)
        .pointingHandCursor()
    }
}
