import SwiftUI

/// A section's page: a scroll view with consistent padding.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
