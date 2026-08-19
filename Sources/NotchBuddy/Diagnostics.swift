import AppKit
import NotchBuddyKit

/// `--info` — what the app resolved about this machine, and what it currently
/// costs. Exists so the geometry and wake budget can be checked against reality
/// rather than trusted, and so a slowness report comes with numbers attached.
@MainActor
enum Diagnostics {

    static func run() -> Never {
        _ = NSApplication.shared  // needed for NSScreen

        print("── écrans ──")
        for screen in NSScreen.screens {
            let id = NotchGeometry.displayID(of: screen).map(String.init) ?? "?"
            let notch = NotchGeometry.notchSize(of: screen)
            let frame = screen.frame
            print(String(
                format: "  id=%-10@ %.0f×%.0f  inset_top=%.0f  encoche=%@",
                id as NSString, frame.width, frame.height,
                screen.safeAreaInsets.top,
                notch.map { String(format: "%.0f×%.0f", $0.width, $0.height) } ?? "aucune"
            ))
        }

        print("\n── géométrie retenue ──")
        if let g = NotchGeometry.resolve() {
            print("  écran        \(g.screenID)")
            print("  cadre        \(Int(g.screenFrame.width))×\(Int(g.screenFrame.height))")
            print("  encoche      \(g.notchSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? "aucune")")
            print("  haut. pastille \(Int(g.pillHeight)) pt")
        } else {
            print("  aucun écran résolu")
        }

        print("\n── budget de réveil ──")
        let wake = WakeCoordinator()
        print("  aucun client        \(fmt(wake.effectiveInterval))")
        for cadence in Cadence.allCases where cadence != .off {
            wake.register(id: "probe", cadence: cadence) {}
            print(String(
                format: "  1 client %-8@ %@  → %.2f réveil/s",
                String(describing: cadence) as NSString,
                fmt(wake.effectiveInterval), wake.wakeupsPerSecond
            ))
        }
        wake.suspend()
        print("  suspendu (veille)   \(fmt(wake.effectiveInterval))  → 0 réveil/s")

        print("\n── budget d'animation ──")
        let budget = AnimationBudget()
        for (visible, busy) in [(false, true), (true, false), (true, true)] {
            budget.update(isVisible: visible, isBusy: busy)
            print(String(
                format: "  visible=%-5@ actif=%-5@ → %-8@ %.0f fps  animations implicites: %@",
                String(visible) as NSString, String(busy) as NSString,
                String(describing: budget.tier) as NSString,
                budget.frameRate,
                budget.allowsImplicitAnimations ? "oui" : "non"
            ))
        }

        print("\n── cadres calculés pour cette machine ──")
        if let g = NotchGeometry.resolve() {
            let pill = CGSize(width: NotchPanel.carrierWidth, height: 32)
            let panel = CGSize(width: NotchPanel.carrierWidth, height: 460)
            for (label, size) in [("pastille", pill), ("panneau ", panel)] {
                for (name, frac) in [("gauche", 0.0), ("centre", 0.5), ("droite", 1.0)] {
                    let r = NotchFrameSolver.frame(size: size, geometry: g, fraction: frac)
                    let flush = r.maxY == g.screenFrame.maxY ? "  ← à ras de l'encoche" : ""
                    print(String(format: "  %@ %-6@ x=%7.1f y=%7.1f  %.0f×%.0f%@",
                                 label, name as NSString, r.minX, r.minY, r.width, r.height,
                                 flush as NSString))
                }
            }
            print("\n── aimants ──")
            for f in [0.02, 0.28, 0.48, 0.97] {
                let snapped = NotchFrameSolver.snap(fraction: CGFloat(f), size: pill, geometry: g)
                let caught = abs(snapped - CGFloat(f)) > 0.0001
                print(String(format: "  %.2f → %.2f  %@", f, snapped,
                             (caught ? "capté" : "laissé libre") as NSString))
            }
        }

        let s = PerfProbe.sample()
        print("\n── coût actuel de ce process ──")
        print(String(format: "  phys_footprint  %.1f Mo   (budget < 40)", s.footprintMB))
        print(String(format: "  RSS             %.1f Mo   (indicatif)", s.residentMB))
        print(String(format: "  réveils inactifs %llu", s.idleWakeups))
        print("")
        exit(0)
    }

    private static func fmt(_ interval: TimeInterval?) -> String {
        interval.map { String(format: "tick %.0fs ", $0) } ?? "aucun timer"
    }
}
