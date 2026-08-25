import SwiftUI

/// A separator, drawn as a line rather than as a `Divider`.
struct VibeDivider: View {
    var body: some View {
        Rectangle()
            .fill(VibeTheme.Border.divider)
            .frame(height: VibeTheme.Border.width)
    }
}
