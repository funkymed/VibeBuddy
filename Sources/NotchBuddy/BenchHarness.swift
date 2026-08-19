import AppKit
import SwiftUI
import NotchBuddyKit

/// The measurement that decides question D5.
///
/// RFC-001 sets a provisional RSS ceiling of 40 MB, and the open question is
/// whether an `NSPanel` hosting SwiftUI can live under it at all. An empty
/// AppKit shell is typically 45–60 MB before a single feature exists, and no
/// amount of optimising the *contents* recovers that.
///
/// So this measures two things and reports the delta:
///
/// - `shell`  — `NSApplication` running, no window. The floor.
/// - `panel`  — plus an `NSPanel` hosting an empty `NSHostingView`. The floor
///              that actually matters, since the pill is permanently on screen.
///
/// Whatever the numbers say, they are the numbers. The point of running this
/// before writing any feature is that the budget is still free to set.
@MainActor
enum BenchHarness {

    enum Mode: String {
        /// NSApplication only, no window. The floor.
        case shell
        /// A bare NSPanel + empty NSHostingView. The D5 measurement.
        case panel
        /// The real NotchPanel showing its pill, hover probe running. What the
        /// user actually pays for once RFC-002 lands.
        case pill
        /// The real NotchPanel, created but hidden. Must cost nothing at all —
        /// this is the measurement the reference implementation would fail,
        /// since it never stops a timer.
        case hidden
        /// Scenario C: the pill on screen with hover tracking live. Since hover
        /// went event-driven this is the same shape as `.pill`; it stays as a
        /// separate label so the CSVs keep their scenario names.
        case interaction
    }

    static func run(mode: Mode, seconds: Double, label: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var panel: NSPanel?
        var notch: NotchPanel?
        switch mode {
        case .shell:
            break
        case .panel:
            panel = makeEmptyPanel()
        case .pill, .hidden, .interaction:
            let wake = WakeCoordinator()
            let n = NotchPanel(wake: wake, budget: AnimationBudget())
            if mode != .hidden { n.show() }
            notch = n
        }

        FileHandle.standardError.write(Data(
            "bench: mode=\(mode.rawValue) duration=\(Int(seconds))s\n".utf8
        ))
        print(PerfProbe.csvHeader)

        // Sample every 5 s, matching perfcheck.sh. The sampler itself is a
        // wakeup, so it is counted and subtracted in the summary below.
        let interval: TimeInterval = 5
        var samples: [PerfSample] = []

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
        timer.setEventHandler {
            MainActor.assumeIsolated {
                let s = PerfProbe.sample()
                samples.append(s)
                print(PerfProbe.csvRow(s, label: label))
                fflush(stdout)
            }
        }
        timer.resume()

        let done = DispatchSource.makeTimerSource(queue: .main)
        done.schedule(deadline: .now() + seconds)
        done.setEventHandler {
            MainActor.assumeIsolated {
                timer.cancel()
                summarise(samples, mode: mode, seconds: seconds)
                _ = panel   // keep both alive for the whole run
                _ = notch
                exit(0)
            }
        }
        done.resume()

        app.run()
        exit(0)
    }

    /// An `NSPanel` configured the way RFC-002 will configure it, hosting an
    /// empty SwiftUI view. Measuring a bare `NSWindow` would understate the
    /// real floor.
    private static func makeEmptyPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: EmptyPillView())
        hosting.frame = panel.contentLayoutRect
        panel.contentView = hosting

        if let geometry = NotchGeometry.resolve() {
            let frame = geometry.screenFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - 100,
                y: frame.maxY - geometry.pillHeight
            ))
        }
        panel.orderFrontRegardless()
        return panel
    }

    private static func summarise(_ samples: [PerfSample], mode: Mode, seconds: Double) {
        guard let last = samples.last, let first = samples.first else {
            FileHandle.standardError.write(Data("bench: no samples\n".utf8))
            return
        }
        let peakRSS = samples.map(\.residentMB).max() ?? 0
        let peakFootprint = samples.map(\.footprintMB).max() ?? 0
        let idleDelta = last.idleWakeups - first.idleWakeups
        let window = last.uptime - first.uptime
        let idlePerSec = window > 0 ? Double(idleDelta) / window : 0
        let cpuPct = window > 0 ? (last.cpuSeconds - first.cpuSeconds) / window * 100 : 0

        // The sampler runs at 0.2 Hz and is part of the harness, not of the app.
        let samplerRate = 0.2

        let out = """

        ── bench summary (\(mode.rawValue), \(Int(seconds))s) ──
        RSS peak            \(String(format: "%.1f", peakRSS)) MB
        footprint peak      \(String(format: "%.1f", peakFootprint)) MB
        CPU (steady)        \(String(format: "%.3f", cpuPct)) %
        idle wakeups/s      \(String(format: "%.3f", idlePerSec)) (dont \(samplerRate)/s de sonde)
        idle wakeups/s net  \(String(format: "%.3f", max(0, idlePerSec - samplerRate)))

        """
        FileHandle.standardError.write(Data(out.utf8))
    }
}

/// Intentionally empty. Anything drawn here would be measured as part of the
/// floor.
private struct EmptyPillView: View {
    var body: some View { Color.clear }
}
