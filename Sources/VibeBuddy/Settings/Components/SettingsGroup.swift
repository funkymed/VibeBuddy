import SwiftUI

/// A titled group of rows, used by every section.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
        }
    }
}
