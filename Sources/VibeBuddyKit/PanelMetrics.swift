import Foundation
import CoreGraphics
import Observation

/// The one animatable dimension SwiftUI owns.
@MainActor
@Observable
public final class PanelMetrics {
    public var drawnWidth: CGFloat

    public init(drawnWidth: CGFloat = 0) {
        self.drawnWidth = drawnWidth
    }
}

/// Timings for the open and close.
///
/// Width animates in SwiftUI, height on the `NSWindow`: same duration, curve and
/// run-loop turn, or the shape stretches. Sequential measured 0.34 s vs 0.26 s.
public enum PanelTiming {
    /// Fraction of the opening animation elapsed before contents are revealed.
    /// See RFC-001, "Notes d'implémentation".
    public static let contentRevealFraction: Double = 0.62

    public static let expand: TimeInterval = 0.26
    public static let collapse: TimeInterval = 0.18
}
