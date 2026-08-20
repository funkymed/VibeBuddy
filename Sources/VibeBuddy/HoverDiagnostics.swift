import AppKit
import NotchBuddyKit

/// Prints the regions that arm the hover, for each state, without a mouse.
///
/// Written because "the panel opens before the pointer reaches it" is a claim
/// about three rects that only exist at runtime — the window frame, the
/// tracking rect, and the polled screen rect — and reasoning about them from
/// the source produced a fix that did not fix it. Driving the states and
/// printing the three is the only way to see which one lags.
@MainActor
enum HoverDiagnostics {

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let panel = NotchPanel(wake: WakeCoordinator(), budget: AnimationBudget())
        // With the buddy and a session count the real app has: the pill's width
        // comes from them, so a bare panel measures a shape nobody ever sees.
        var loader = BuddyLoader()
        panel.setBuddy(loader.load(
            id: UserDefaults.standard.string(forKey: "notchbuddy.buddy") ?? "emoji").manifest)
        panel.setSessionCount(2)
        panel.show()
        settle(0.4)

        print("── zones de survol par état ──")
        report(panel, "pastille (avant toute ouverture)")

        panel.debugSetState(.panel)
        report(panel, "panneau ouvert")

        panel.debugSetState(.pill)
        report(panel, "replié — animation en cours")

        // The collapse is animated, so the interesting rect is the one *after*
        // the frame has finished moving. That is exactly the window in which a
        // stale tracking rect survives.
        settle(1.2)
        report(panel, "replié — animation terminée")

        // The two setters the real app calls while collapsed. Each one resizes
        // the pill, and a region that does not follow is a region that arms the
        // hover outside the black.
        panel.setSessionCount(0)
        settle(0.3)
        report(panel, "replié — 0 session")

        panel.setSessionCount(3)
        settle(0.3)
        report(panel, "replié — 3 sessions")
        print("")
        exit(0)
    }

    /// The rect the view actually paints, found by scanning the rendered
    /// bitmap for anything that is not transparent.
    ///
    /// This is the only measurement that answers the user's complaint in the
    /// user's terms. Every other number here comes from the same layout code
    /// the hover regions come from, so they agree with each other by
    /// construction and would agree even if both were wrong. The pixels cannot
    /// lie about where the black is.
    static func paintedRect(of view: NSView) -> CGRect {
        guard view.bounds.width > 1, view.bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return .zero }
        view.cacheDisplay(in: view.bounds, to: rep)

        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.05
                else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return .zero }
        // Back to points: the bitmap is in device pixels on a Retina display.
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        return CGRect(
            x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale)
    }

    /// Let the run loop deliver frame changes and animations.
    private static func settle(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    private static func report(_ panel: NotchPanel, _ label: String) {
        let frame = panel.frame
        let tracking = panel.debugTrackingRect
        let polled = panel.debugPolledRect
        let mouse = NSEvent.mouseLocation
        print("  \(label)  · état=\(panel.debugState)")
        print(String(format: "    souris    x=%7.1f y=%7.1f  %@",
                     mouse.x, mouse.y,
                     (panel.debugPolledRect.contains(mouse) ? "DANS la pastille" : "dehors") as NSString))
        print(String(format: "    fenêtre   x=%7.1f y=%7.1f  %6.1f × %5.1f",
                     frame.minX, frame.minY, frame.width, frame.height))
        print(String(format: "    suivi     x=%7.1f y=%7.1f  %6.1f × %5.1f  (coord. vue)",
                     tracking.minX, tracking.minY, tracking.width, tracking.height))
        print(String(format: "    sondé     x=%7.1f y=%7.1f  %6.1f × %5.1f  (écran)",
                     polled.minX, polled.minY, polled.width, polled.height))
        let painted = panel.debugPaintedRect
        print(String(format: "    peint     x=%7.1f y=%7.1f  %6.1f × %5.1f  (coord. vue)",
                     painted.minX, painted.minY, painted.width, painted.height))
        if painted.width > 0, tracking.width > painted.width + 1 {
            print(String(format: "    ⚠ la zone de survol dépasse le noir de %.0f pt",
                         tracking.width - painted.width))
        }
    }
}
