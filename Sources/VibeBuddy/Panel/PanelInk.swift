import SwiftUI

/// The panel's ink scale: every shade of white it may draw with.
enum PanelInk {
    static let primary = Color.white.opacity(0.90)

    static let secondary = Color.white.opacity(0.60)

    static let tertiary = Color.white.opacity(0.35)

    static let disabled = Color.white.opacity(0.20)

    static let surface = Color.white.opacity(0.05)

    static let stroke = Color.white.opacity(0.08)
}
