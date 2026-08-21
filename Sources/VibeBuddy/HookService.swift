import AppKit
import Foundation
import VibeBuddyKit
import VibeHookProtocol

/// Owns the hook socket for the life of the app.
///
/// RFC-006 built `HookSocketServer` and never started it: the transport existed
/// and nothing had ever listened on it. This is the thing that listens. RFC-007,
/// T0.
///
/// **It must never block Claude Code.** Every event the queue has not claimed
/// is answered `nil` — the hook writes nothing and Claude falls back to its own
/// prompt, exactly as if the app were not running.
@MainActor
final class HookService {

    private var server: HookSocketServer?
    private let sink: HookEventSink
    /// The requests waiting on a person. Held here so the app can answer them
    /// all on the way out.
    let permissions: PermissionQueue
    private var frontmostObserver: NSObjectProtocol?

    init(permissions: PermissionQueue = PermissionQueue()) {
        self.permissions = permissions
        self.sink = PermissionSink(queue: permissions)
    }

    /// Starts listening. A failure here is logged and swallowed: no socket
    /// means no interception, which is a lesser thing than no app.
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
    ///
    /// **No timer, and no poll.** The exit criterion asks for zero wakeups
    /// while a request is waiting, so every expiry rides an event the machine
    /// was going to deliver anyway: the socket hanging up (handled inside the
    /// queue), the transcript being written to (`SessionCoordinator.onChange`,
    /// itself driven by `ProjectsWatcher`), and an application coming forward.
    func watchForExpiry() {
        guard frontmostObserver == nil else { return }
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireIfHostIsFrontmost() }
        }
    }

    /// **Deliberately does nothing.** Kept as the record of an expiry that was
    /// wired, measured against a real session on 2026-08-21, and taken out.
    ///
    /// The idea — a request whose own terminal is in front is a second prompt
    /// for one question — is true of an *alert* and false of a *permission*:
    /// the user is in that terminal by definition when the agent asks, because
    /// that is where they just typed. Wired, it closed the panel before anyone
    /// could reach it, on the first application-activation event that came
    /// along. « Je n'ai pas eu le temps de répondre, ça s'est refermé trop
    /// vite. »
    ///
    /// The hang-up detection already covers the real case: if they answer in
    /// the terminal, the peer goes away and the panel goes with it.
    private func expireIfHostIsFrontmost() {}

    /// Called with every session refresh — already event-driven, already
    /// happening. Costs nothing while the queue is empty, which is almost
    /// always.
    func expireStale(against sessions: [AgentSession]) {
        guard !permissions.isEmpty else { return }
        permissions.expireStale { model in
            // By `sessionID` — the only appariement that means anything.
            if let id = model.sessionID {
                // Known: its own activity decides.
                if let match = sessions.first(where: { $0.id == id }) {
                    return match.lastActivity
                }
                // Named a session we do not know. **No fallback**: measured on
                // 2026-08-21, falling back to `cwd` killed a live permission in
                // 3,6 s because a *different* session in the same folder was
                // writing. That is the normal case — the agent asks for a
                // permission in the repository the user is already working in —
                // so the fallback dismissed the panel almost every time.
                return nil
            }
            // No session id at all: `cwd` is all there is, and only when a
            // single session can be meant by it. Two sessions in one folder
            // make the answer a guess, and a wrong guess here throws away a
            // question the user never got to see.
            guard let cwd = model.cwd else { return nil }
            let candidates = sessions.filter { $0.cwd == cwd }
            return candidates.count == 1 ? candidates[0].lastActivity : nil
        }
    }

    /// Hangs up on everything, and unlinks the socket.
    ///
    /// Called from `applicationWillTerminate`: a stale socket file left behind
    /// is one a later `vibe-hook` connects to and waits on, and a hook that
    /// waits is a Claude Code that waits.
    func stop() {
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
        frontmostObserver = nil
        // Answer before hanging up. A queue that dies holding continuations is
        // a Claude Code that waits out its 120 s timeout, once per request.
        permissions.drain()
        guard let server else { return }
        self.server = nil
        Task { await server.stop() }
    }
}

// The queue answers `nil` to everything it has not claimed, which is the
// documented meaning of "no opinion" in `HookEventSink`: the hook writes
// nothing and Claude Code shows its own prompt. RFC-003 will take the mode
// updates the same way.
