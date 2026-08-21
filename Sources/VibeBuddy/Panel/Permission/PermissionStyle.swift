import SwiftUI

/// The two colours the permission panel is allowed to draw that are not white.
///
/// `PanelInk` is deliberately a scale of whites and stays that way. Red and
/// green here are not decoration: they are the difference between what is being
/// removed and what is being added, and between the answer that stops Claude and
/// the one that lets it through. Same precedent as `SessionStateStyle`, which
/// also names its semantic colours in one place rather than inline in views.
///
/// Kept at 0.85 rather than full saturation: on the pure black of the notch a
/// saturated red vibrates against its own background.
enum PermissionInk {
    static let removed = Color.red.opacity(0.85)

    static let added = Color.green.opacity(0.85)

    /// Behind a diff row. Faint enough that the text stays the thing being read.
    static func wash(_ colour: Color) -> Color { colour.opacity(0.12) }
}

extension View {
    /// The sunken, scrollable block a summary pours its content into.
    ///
    /// Shared by the command block and the diff block, which arrived at the same
    /// four modifiers from two directions; a third copy would have been the one
    /// that drifts. `maxHeight` is the only thing they disagree on — a diff earns
    /// more rows than a command line.
    ///
    /// The height is a ceiling, not a size: the content is already truncated at
    /// parse time, so this bounds the panel, it does not bound the data.
    func permissionBlock(maxHeight: CGFloat) -> some View {
        self
            .frame(maxHeight: maxHeight)
            .scrollBounceBehavior(.basedOnSize)
            .background(RoundedRectangle(cornerRadius: 8).fill(PanelInk.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PanelInk.stroke))
    }
}
