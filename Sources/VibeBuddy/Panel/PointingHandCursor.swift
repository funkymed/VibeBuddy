import AppKit
import SwiftUI

/// Turns the pointer into a hand over something clickable. See RFC-008,
/// "Notes d'implémentation".
///
/// Every `NSCursor.push()` needs its pop, and a row can be torn down while the
/// pointer is still inside it — `onDisappear` is the safety net, do not remove it.
struct PointingHandCursor: ViewModifier {

    /// Only clickable things get the hand. A dead session is still a row.
    let isEnabled: Bool
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                onHoverChange(inside)
                guard isEnabled else { return }
                if inside, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                guard pushed else { return }
                NSCursor.pop()
                pushed = false
            }
    }
}

extension View {
    func pointingHandCursor(
        _ isEnabled: Bool = true,
        onHoverChange: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(PointingHandCursor(isEnabled: isEnabled, onHoverChange: onHoverChange))
    }
}
