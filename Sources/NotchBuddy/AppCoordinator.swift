import AppKit
import NotchBuddyKit

/// Owns the object graph and the app's relationship with the system.
///
/// The reference implementation injects nine objects straight into a single
/// SwiftUI view (`AppDelegate.swift:5-15`), which is the root cause of its
/// 3 738-line view file. Here the coordinator holds the graph and hands out
/// only what each layer needs.
///
/// Its second job is the one the reference never does at all: **stopping**.
/// Nothing in that codebase ever calls `stop()`, so its timers keep firing with
/// the lid shut. Sleep and screen lock suspend the wake coordinator here, which
/// tears the shared timer down to zero.
@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {

    let wake = WakeCoordinator()
    let animation = AnimationBudget()
    private(set) var geometry: NotchGeometry?
    private var panel: NotchPanel?

    /// Until RFC-003 drives visibility from live sessions, the pill is shown on
    /// launch so RFC-002 can be exercised at all.
    var showPillOnLaunch = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        geometry = NotchGeometry.resolve()
        observeSystemState()

        let panel = NotchPanel(wake: wake, budget: animation)
        self.panel = panel
        if showPillOnLaunch { panel.show() }

        PerfProbe.log.info("launched · notch=\(self.geometry?.hasNotch ?? false, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        wake.suspend()
    }

    // MARK: - System state

    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter

        workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enterLowPower("sleep") }
        }

        workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.leaveLowPower("wake") }
        }

        // Screen lock is not on NSWorkspace — it only arrives on the
        // distributed centre, undocumented but stable for many releases.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enterLowPower("lock") }
        }
        distributed.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.leaveLowPower("unlock") }
        }

        // Screen layout changes invalidate the resolved notch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let resolved = NotchGeometry.resolve(preferredScreenID: self.geometry?.screenID)
                guard resolved != self.geometry else { return }
                self.geometry = resolved
                self.panel?.refreshGeometry()
                PerfProbe.log.info("screen layout changed")
            }
        }
    }

    private func enterLowPower(_ reason: String) {
        wake.suspend()
        animation.set(.still)
        panel?.hide()
        PerfProbe.log.info("suspended (\(reason, privacy: .public))")
    }

    private func leaveLowPower(_ reason: String) {
        wake.resume()
        if showPillOnLaunch { panel?.show() }
        PerfProbe.log.info("resumed (\(reason, privacy: .public))")
    }
}
