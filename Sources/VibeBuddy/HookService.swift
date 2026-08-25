import AppKit
import Foundation
import VibeBuddyKit
import VibeHookProtocol

/// Owns the hook socket for the life of the app.
@MainActor
final class HookService {
    private var server: HookSocketServer?
    private let sink: HookEventSink
    /// The requests waiting on a person.
    let permissions: PermissionQueue
    private var frontmostObserver: NSObjectProtocol?

    init(permissions: PermissionQueue = PermissionQueue()) {
        self.permissions = permissions
        self.sink = PermissionSink(queue: permissions)
    }

    /// Starts listening.
    func start() {
        guard server == nil else { return }
        let server = HookSocketServer(sink: sink)
        self.server = server
        Task {
            do {
                try await server.start()
                PerfProbe.log.info(
                    "hook: à l'écoute sur \(HookWire.socketPath, privacy: .public)")
            } catch {
                PerfProbe.log.error(
                    "hook: écoute impossible — \(String(describing: error), privacy: .public)")
                await MainActor.run { self.server = nil }
            }
        }
    }

    /// The three expiries of T3, wired to things that already happen.
    func watchForExpiry() {
        guard frontmostObserver == nil else { return }
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireIfHostIsFrontmost() }
        }
    }

    /// Deliberately does nothing. Kept as the record of an expiry that was wired,
    /// measured against a real session on 2026-08-21, and taken out.
    private func expireIfHostIsFrontmost() {}

    /// Called with every session refresh — already event-driven, already happening.
    func expireStale(against sessions: [AgentSession]) {
        guard !permissions.isEmpty else { return }
        permissions.expireStale { model in
            // By `sessionID` — the only appariement that means anything.
            if let id = model.sessionID {
                // Known: its own activity decides.
                if let match = sessions.first(where: { $0.id == id }) {
                    return match.lastActivity
                }
                // Named a session we do not know. No fallback: measured on
                // 2026-08-21, falling back to `cwd` killed a live permission in 3,6 s
                // because a *different* session in the same folder was writing.
                return nil
            }
            // No session id at all: `cwd` is all there is, and only when a single
            // session can be meant by it.
            guard let cwd = model.cwd else { return nil }
            let candidates = sessions.filter { $0.cwd == cwd }
            return candidates.count == 1 ? candidates[0].lastActivity : nil
        }
    }

    /// Hangs up on everything, and unlinks the socket.
    func stop() {
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
        frontmostObserver = nil
        // Answer before hanging up. A queue that dies holding continuations is a Claude
        // Code that waits out its 120 s timeout, once per request.
        permissions.drain()
        guard let server else { return }
        self.server = nil
        Task { await server.stop() }
    }
}

// The queue answers `nil` to everything it has not claimed, which is the documented
// meaning of "no opinion" in `HookEventSink`: the hook writes nothing and Claude Code
// shows its own prompt.
