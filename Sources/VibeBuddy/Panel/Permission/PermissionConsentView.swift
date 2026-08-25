import SwiftUI
import VibeBuddyKit

/// What « Toujours autoriser » shows before it writes anything.
struct PermissionConsentView: View {
    let rule: String
    /// The unified diff of the file as it is against the file as it would be.
    let diff: String
    let backupDirectory: String
    let l10n: Strings
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.consentTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PanelInk.secondary)
                    .tracking(0.8)
                Text(rule)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelInk.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ScrollView {
                Text(diff)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(PanelInk.secondary)
                    // Deliberately not `.textSelection(.enabled)`: it installs an
                    // I-beam that wins over everything the panel puts on the pointer,
                    // so the hand flickered on every button and row.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .permissionBlock(maxHeight: 190)

            // Said out loud, because it is the thing that makes a wrong write
            // repairable — and the user cannot see the folder from here.
            Text(l10n.consentBackup(backupDirectory))
                .font(.system(size: 10))
                .foregroundStyle(PanelInk.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: VibeTheme.Spacing.s) {
                Spacer(minLength: 0)
                VibeButton(title: l10n.consentCancel, role: .neutral, action: onCancel)
                // Writing to the user's own settings file is the act this whole screen
                // exists to ask about, so it is the one thing on it the eye should land
                // on.
                VibeButton(title: l10n.consentConfirm, role: .accent,
                           action: onConfirm)
            }
        }
    }
}
