import SwiftUI
import VibeBuddyKit

/// A command line, and whatever Claude said it was for.
struct ShellSummaryView: View {
    let command: String
    /// Claude's own one-liner.
    var description: String?
    let l10n: Strings

    /// Tall enough for a long pipeline, short enough to leave the decision bar on
    /// screen.
    private static let maxHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(PanelInk.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            commandBlock
        }
    }

    private var commandBlock: some View {
        ScrollView(.vertical) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(PanelInk.primary)
                // Selectable so a command too long to read can be pasted somewhere it
                // can be.
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .permissionBlock(maxHeight: Self.maxHeight)
    }
}
