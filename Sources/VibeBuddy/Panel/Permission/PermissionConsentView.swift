import SwiftUI
import VibeBuddyKit

/// What « Toujours autoriser » shows before it writes anything. RFC-007, T8.
///
/// The user's `~/.claude/settings.json` is eleven kilobytes of hand-edited
/// settings, and this is the app asking to edit it. The parade to risk R1 is
/// four things, and three of them are already inside `ClaudeSettingsWriter`:
/// a timestamped backup, an atomic replace, the order preserved. The fourth is
/// this screen — **consent, on the exact diff**, not on a sentence describing
/// it. A summary the user has to trust is how a wrong write gets approved.
///
/// It is a state of the permission panel rather than a sheet: an `NSPanel` that
/// is not key cannot host a modal sensibly, and a second window over the notch
/// is a second thing to dismiss.
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
                    .textSelection(.enabled)
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

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(l10n.consentCancel, action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(PanelInk.secondary)
                Button(l10n.consentConfirm, action: onConfirm)
                    .buttonStyle(.plain)
                    .foregroundStyle(PermissionInk.added)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 13))
        }
    }
}
