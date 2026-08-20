import AppKit
import VibeBuddyKit

/// Translucent ghost showing where the pill lands if released now — the magnets
/// fire on release. Created lazily and torn down at the end of every drag.
@MainActor
final class SnapPreviewPanel {

    private var panel: NSPanel?

    /// Show the ghost at `fraction`, or hide it when the drag is not near a magnet.
    func show(fraction: CGFloat, size: CGSize, geometry: NotchGeometry) {
        let snapped = NotchFrameSolver.snap(fraction: fraction, size: size, geometry: geometry)
        // No magnet in reach — nothing to preview.
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
