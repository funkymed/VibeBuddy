import SwiftUI
import VibeBuddyKit

/// The tongue under the notch: a glyph drawn like the eyes, the project, and how many
/// other sessions are waiting to be seen.
struct AlertTongueView: View {
    let alert: SessionAlert
    /// Sessions behind this one.
    let others: Int
    let colour: Color

    /// A window's title bar: the height every Mac user already reads as « a bar ».
    /// Measured from AppKit rather than written down, so it follows the system: 32 pt
    /// measured on macOS 26 (Darwin 25.5).
    static let height: CGFloat = NSWindow.frameRect(
        forContentRect: .zero, styleMask: [.titled]).height
    /// How far each side slants in, top to bottom: wide where it leaves the notch,
    /// narrower where it ends.
    nonisolated static let taper: CGFloat = 18
    /// The eyes' own cell: six of them are 18 pt, which a title-bar height holds with
    /// room above and below.
    static let glyphPitch: CGFloat = BuddyView.pixelSize

    /// Starts tucked up behind the notch and slides down out of it. The window is the
    /// clip: whatever sits above its top edge is not drawn, so the tongue appears to come
    /// out from under the pill rather than fade in over it.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        tongue
            .offset(y: revealed || reduceMotion ? 0 : -Self.height)
            // Once, when the window is shown: a new count or a new head swaps the
            // content in place, it does not slide again. Critically damped: an
            // overshoot would drop the tongue below its seat for a moment and open a
            // gap under the pill. Then nothing — no clock survives the arrival.
            .onAppear {
                withAnimation(.spring(response: 0.38, dampingFraction: 1)) { revealed = true }
            }
    }

    private var tongue: some View {
        HStack(spacing: 10) {
            AlertGlyphView(glyph: AlertGlyph(alert.kind), colour: colour, pitch: Self.glyphPitch)
            Text(alert.projectName)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelInk.primary)
                .lineLimit(1)
                // Truncated, never overflowing: the window is capped at the notch.
                .truncationMode(.tail)
            if others > 0 {
                Text("+\(others)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelInk.secondary)
                    .fixedSize()
            }
        }
        // The content sits in the narrow bottom half, clear of both slants.
        .padding(.horizontal, Self.taper + 12)
        .frame(height: Self.height)
        .background(TongueShape(closed: true).fill(.black))
        // The pill's own edge, down the sides and round the bottom — never across the
        // top, which is where the tongue joins the pill.
        .overlay(TongueShape(closed: false)
            .stroke(VibeTheme.Border.strong, lineWidth: VibeTheme.Border.width))
    }
}

/// Wide at the top, narrower at the bottom. Each side is one straight segment; the
/// corners are arcs tangent to both segments they join (`addArc(tangent1End:…)`), so
/// no edge kinks where one piece meets the next. At the top a short lip runs outward
/// into the pill, rounded concave, so the tongue flows out of the notch. Open, it is
/// the outline without its top edge.
struct TongueShape: Shape {
    let closed: Bool
    var taper: CGFloat = AlertTongueView.taper
    /// Width of the lip at each top corner, before the side turns down.
    var lip: CGFloat = 10
    var flareRadius: CGFloat = 8
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        // Half a line in, so the stroke lands inside the frame like `strokeBorder`.
        let inset = closed ? 0 : VibeTheme.Border.width / 2
        let box = rect.insetBy(dx: inset, dy: 0)
        let top = box.minY, bottom = box.maxY - inset
        let t = min(taper, box.width / 4)
        let a = min(lip, t)

        var path = Path()
        path.move(to: CGPoint(x: box.minX, y: top))
        path.addArc(tangent1End: CGPoint(x: box.minX + a, y: top),
                    tangent2End: CGPoint(x: box.minX + t, y: bottom), radius: flareRadius)
        path.addArc(tangent1End: CGPoint(x: box.minX + t, y: bottom),
                    tangent2End: CGPoint(x: box.maxX - t, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: box.maxX - t, y: bottom),
                    tangent2End: CGPoint(x: box.maxX - a, y: top), radius: radius)
        path.addArc(tangent1End: CGPoint(x: box.maxX - a, y: top),
                    tangent2End: CGPoint(x: box.maxX, y: top), radius: flareRadius)
        path.addLine(to: CGPoint(x: box.maxX, y: top))
        if closed { path.closeSubpath() }
        return path
    }
}
