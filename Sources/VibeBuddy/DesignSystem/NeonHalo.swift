import SwiftUI

/// A blurred outline behind a shape: the one way this app draws light.
///
/// **Why a shared modifier.** The halo has exactly one correct implementation
/// here — a stroke that is drawn and then blurred — and it was found the hard
/// way: `.shadow` inside a `.background` never leaves the view's own bounds,
/// measured twice at `(4,9,16)` two points out against `(4,8,14)` for the panel.
/// A second copy of that lesson elsewhere in the code would be a second chance
/// to get it wrong.
///
/// **And why it must stay rare.** Three stacked blurs on the buddy's face cost
/// this repository 38 Mo and 5,4 wakeups a second where one costs 23 Mo and
/// 0,2. Every caller here lights at most one element at a time — the answer
/// under the pointer, the row under the pointer, the action that goes forward.
extension View {

    /// - Parameters:
    ///   - shape: the outline to light. The caller's own shape, so the halo
    ///     follows its corners exactly.
    ///   - isOn: false draws nothing at all, not a transparent layer.
    ///   - colour: the light. Defaults to VibeBuddy's blue.
    func neonHalo<S: Shape>(
        _ shape: S,
        isOn: Bool,
        colour: Color = VibeTheme.Glow.outer,
        radius: CGFloat = VibeTheme.Glow.radius
    ) -> some View {
        background {
            if isOn {
                shape
                    .stroke(colour, lineWidth: 2)
                    .blur(radius: radius)
            }
        }
    }
}
