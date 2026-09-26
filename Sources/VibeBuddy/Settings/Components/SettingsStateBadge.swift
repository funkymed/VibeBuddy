import SwiftUI

/// « autorisé », « absent », « illisible »: a word in its own colour.
struct SettingsStateBadge: View {
    let text: String
    let colour: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(colour)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(colour.opacity(0.12)))
            .fixedSize()
    }
}
