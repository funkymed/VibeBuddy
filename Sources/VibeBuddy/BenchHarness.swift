import AppKit
import SwiftUI
import VibeBuddyKit

/// Measures the D5 floor against RFC-001's 40 MB ceiling: an empty AppKit shell
/// is typically 45–60 MB before a single feature exists.
@MainActor
enum BenchHarness {

    enum Mode: String {
        /// `NSApplication` only, no window. The floor.
        case shell
        /// A bare `NSPanel` + empty `NSHostingView`. The D5 measurement.
        case panel
        /// The real `NotchPanel` showing its pill, hover probe running.
        case pill
        /// The real `NotchPanel`, created but hidden. Must cost nothing at all.
        case hidden
        /// Scenario C. Same shape as `.pill` since hover went event-driven; kept
        /// as a separate label so the CSVs keep their scenario names.
        case interaction
        /// The session pipeline alone: FSEvents plus the lazy liveness poll.
        case sessions
        /// The whole app, coordinator included.
        case app
    }

    static func run(mode: Mode, seconds: Double, label: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var panel: NSPanel?
        var notch: NotchPanel?
        var sessionCoordinator: SessionCoordinator?
        var appCoordinator: AppCoordinator?
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
        case .app:
            // Delegate only: `NSApp.run()` posts the launch notification itself,
            // and calling it here as well built the whole graph twice — two
            // panels, two session coordinators, two sets of FSEvents watchers.
            // Every `--bench app` figure before 2026-08-20 measured that double.
            let coordinator = AppCoordinator()
            NSApp.delegate = coordinator
            coordinator.onBuddyReload = { id in
                FileHandle.standardError.write(Data("  ↻ buddy rechargé : \(id)\n".utf8))
            }
            appCoordinator = coordinator
        case .sessions:
            // No `AppCoordinator` here: alerts are printed, never rendered.
            let wake = WakeCoordinator()
            let coordinator = SessionCoordinator(wake: wake)
            // Latency is measured against the transcript's own mtime, not a wall
            // clock the harness controls.
            nonisolated(unsafe) var seen = Set<String>()
            coordinator.onChange = { list in
                let now = Date()
                for session in list where session.isLive && !seen.contains(session.id) {
                    seen.insert(session.id)
                    let lag = now.timeIntervalSince(session.lastActivity)
                    FileHandle.standardError.write(Data(String(
                        format: "  + %@ détectée %.2f s après sa dernière écriture\n",
                        session.projectName, lag).utf8))
                }
                let live = list.filter(\.isLive).count
                FileHandle.standardError.write(Data(
                    "  sessions: \(live) vivantes / \(list.count)\n".utf8))
            }
            coordinator.onAlert = { alert in
                FileHandle.standardError.write(Data(String(
                    format: "  ★ ALERTE  %@  %@\n",
                    alert.projectName, alert.kind.rawValue).utf8))
            }
            coordinator.start()
            sessionCoordinator = coordinator
            // Without this, "no alert" and "policy did its job" look alike.
            nonisolated(unsafe) var reported = 0
            let suppressionTimer = DispatchSource.makeTimerSource(queue: .main)
            suppressionTimer.schedule(deadline: .now() + 3, repeating: 3)
            suppressionTimer.setEventHandler { [weak coordinator] in
                MainActor.assumeIsolated {
                    guard let list = coordinator?.suppressedAlerts, list.count > reported else { return }
                    for entry in list[reported...] {
                        FileHandle.standardError.write(Data(String(
                            format: "  ✕ supprimée  %@  %@  (%@)\n",
                            entry.alert.projectName, entry.alert.kind.rawValue,
                            entry.reason).utf8))
                    }
                    reported = list.count
                }
            }
            suppressionTimer.resume()
        }

        FileHandle.standardError.write(Data(
            "bench: mode=\(mode.rawValue) duration=\(Int(seconds))s\n".utf8
        ))
        print(PerfProbe.csvHeader)

        // Every 5 s, matching perfcheck.sh. The sampler is itself a wakeup, so
        // it is subtracted in the summary below.
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
                _ = panel   // keep everything alive for the whole run
                _ = notch
                _ = sessionCoordinator
                _ = appCoordinator
                FileHandle.standardError.write(Data("bench: fin normale du minuteur\n".utf8))
                exit(0)
            }
        }
        done.resume()

        app.run()
        // `app.run()` is not supposed to return here: the run ends on the
        // `done` timer above. If it does, something terminated the
        // application, and a run that stops early has been seen three times on
        // this project without ever being explained. Say so out loud rather
        // than exiting quietly with a short, valid-looking CSV.
        FileHandle.standardError.write(Data(
            "bench: ARRÊT PRÉMATURÉ — app.run() a rendu la main avant le minuteur\n".utf8))
        exit(0)
    }

    /// Configured as RFC-002 configures it: a bare `NSWindow` understates the floor.
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

/// Intentionally empty: anything drawn here is measured as part of the floor.
private struct EmptyPillView: View {
    var body: some View { Color.clear }
}
