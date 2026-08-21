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
public extension PanelMetrics {
    /// Where the deployed panel's contents start. Shared because the buddy
    /// travels to exactly this point while the shape is still growing, and a
    /// second copy of the number is a second thing to keep in step.
    static let contentInset = CGSize(width: 20, height: 16)
}

public enum PanelTiming {
    /// Fraction of the opening animation elapsed before contents are revealed.
    ///
    /// Was 0.62, which put the rows on screen at their final width while the
    /// shape still had a third of its growth to go: they read as pasted on
    /// rather than as the panel's own contents. Now they arrive as it settles.
    /// See RFC-001, "Notes d'implémentation".
    public static let contentRevealFraction: Double = 0.9

    public static let expand: TimeInterval = 0.26
    public static let collapse: TimeInterval = 0.18
}
