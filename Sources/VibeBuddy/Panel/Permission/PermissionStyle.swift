import SwiftUI

/// The two colours the permission panel is allowed to draw that are not white.
enum PermissionInk {
    static let removed = Color.red.opacity(0.85)

    static let added = Color.green.opacity(0.85)

    /// Behind a diff row.
    static func wash(_ colour: Color) -> Color { colour.opacity(0.12) }
}

extension View {
    /// The sunken, scrollable block a summary pours its content into.
    func permissionBlock(maxHeight: CGFloat) -> some View {
        self
            .frame(maxHeight: maxHeight)
            .scrollBounceBehavior(.basedOnSize)
            .background(
                RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                    .fill(VibeTheme.Surface.sunken))
            .overlay(
                RoundedRectangle(cornerRadius: VibeTheme.Radius.medium)
                    .strokeBorder(VibeTheme.Border.subtle, lineWidth: VibeTheme.Border.width))
    }
}
