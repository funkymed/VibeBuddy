import SwiftUI

/// A blurred outline behind a shape: the one way this app draws light. And why it must
/// stay rare. Three stacked blurs on the buddy's face cost this repository 38 Mo and
/// 5,4 wakeups a second where one costs 23 Mo and 0,2.
extension View {
    /// - Parameters: - shape: the outline to light.
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
