import SwiftUI
import VibeBuddyKit

/// What can be done to the buddy as a whole: duplicate, export, reset, delete.
///
/// See RFC-010, "Notes d'implémentation".
struct BuddyActionsRow: View {
    let strings: SettingsStrings
    /// The buddy carries edits in the override layer, so resetting has an effect.
    let hasEdits: Bool
    /// The buddy was created in the app and has no file behind it.
    let isCreated: Bool
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onReset: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(strings.duplicate, action: onDuplicate)
                .pointingHandCursor()
            Button(strings.export, action: onExport)
                .pointingHandCursor()
            Spacer()
            if hasEdits {
                Button(strings.resetBuddy, role: .destructive, action: onReset)
                .pointingHandCursor()
            }
            if isCreated {
                Button(strings.deleteBuddy, role: .destructive, action: onDelete)
                .pointingHandCursor()
            }
        }
    }
}
