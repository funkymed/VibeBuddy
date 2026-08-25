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

/// Timings for the open and close. Sequential measured 0.34 s vs 0.26 s.
public extension PanelMetrics {
    /// Where the deployed panel's contents start.
    static let contentInset = CGSize(width: 20, height: 16)
}

public enum PanelTiming {
    /// Fraction of the opening animation elapsed before contents are revealed.
    public static let contentRevealFraction: Double = 0.9

    public static let expand: TimeInterval = 0.26
    public static let collapse: TimeInterval = 0.18
}
