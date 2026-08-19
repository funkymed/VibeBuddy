import Foundation
import CoreGraphics
import Observation

/// The one animatable dimension SwiftUI owns.
///
/// The window is always `carrierWidth` points wide so the frame never jumps
/// sideways; what actually changes width is the shape *drawn* inside it. Keeping
/// that in an observable lets the width animate in SwiftUI while the height
/// animates on the `NSWindow` — which is what makes a two-phase unfold possible
/// at all.
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
/// Both axes move together: the width in SwiftUI, the height on the `NSWindow`.
/// Two animation engines that have to land at the same instant — same duration,
/// same curve, started in the same turn of the run loop. Any drift between them
/// shows as the shape stretching before it settles.
///
/// A sequential version (widen, then drop) was tried and dropped: it read well
/// but took 0.34 s against 0.26 s, and the panel opens on every hover.
public enum PanelTiming {
    /// Opening is a request to see something, so it gets room to unfold.
    public static let expand: TimeInterval = 0.26
    /// Closing is a dismissal — dragging it out leaves the panel covering the
    /// menu bar longer than the user asked for.
    public static let collapse: TimeInterval = 0.18
}
