import AppKit
import NotchBuddyKit

/// Translucent ghost showing where the pill will land if released now.
///
/// Without it a drag is a guess: the magnets fire on release, so the user only
/// discovers the snap after committing to it. The ghost turns that into a
/// preview — and it is also the only feedback that a magnet is in reach at all.
///
/// Created lazily and torn down at the end of every drag: a second window that
/// lingers is a second window costing memory for nothing.
@MainActor
final class SnapPreviewPanel {

    private var panel: NSPanel?

    /// Show the ghost at `fraction`, or hide it when the drag is not near a magnet.
    func show(fraction: CGFloat, size: CGSize, geometry: NotchGeometry) {
        let snapped = NotchFrameSolver.snap(fraction: fraction, size: size, geometry: geometry)
        // No magnet in reach — nothing to preview, so don't distract with one.
        guard abs(snapped - fraction) > 0.0001 else {
            hide()
            return
        }

        let frame = NotchFrameSolver.frame(size: size, geometry: geometry, fraction: snapped)
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Just below the pill, so the ghost never covers what is being dragged.
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = NSView()
        view.wantsLayer = true
        if let layer = view.layer {
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
            layer.borderWidth = 1
            layer.cornerRadius = 10
        }
        p.contentView = view
        return p
    }
}
