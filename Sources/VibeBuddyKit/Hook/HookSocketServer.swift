import Darwin
import Foundation
import VibeHookProtocol

/// What the app does with an event the hook forwarded.
///
/// RFC-007 implements this. Returning `nil` for a blocking event means "no
/// opinion": the hook then writes nothing and Claude Code shows its own prompt.
public protocol HookEventSink: Sendable {
    func handle(_ request: HookRequest, from pid: pid_t?) async -> HookDecision?
}

/// Listens on the Unix socket the `vibe-hook` binary connects to.
///
/// Event-driven throughout — a `DispatchSource` on the listening descriptor,
/// another on each connection. No timer anywhere: the process sleeps until the
/// kernel has something to say, which is what keeps scenario A at zero wakeups
/// (D3). See RFC-006.
public actor HookSocketServer {

    private let path: String
    private let sink: HookEventSink
    private var listening: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    /// Connections currently being served, so `stop()` can hang up on them.
    private var open: Set<Int32> = []

    public init(path: String = HookWire.socketPath, sink: HookEventSink) {
        self.path = path
        self.sink = sink
    }

    public var socketPath: String { path }
    public var isListening: Bool { listening >= 0 }
    public var openConnections: Int { open.count }

    public func start() throws {
        guard listening < 0 else { return }
        listening = try HookSocket.listen(at: path)
        let source = DispatchSource.makeReadSource(
            fileDescriptor: listening, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.acceptOne() }
        }
        source.resume()
        acceptSource = source
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        for fd in open { close(fd) }
        open.removeAll()
        if listening >= 0 { close(listening) }
        listening = -1
        unlink(path)
    }

    // MARK: - One connection

    /// Set `VIBEBUDDY_HOOK_TRACE` to see which call returned what, in order.
    /// RFC-006 T11 asks for exactly this rather than another guess at the
    /// architecture.
    private static let trace = ProcessInfo.processInfo.environment["VIBEBUDDY_HOOK_TRACE"] != nil

    private static func note(_ message: @autoclosure () -> String) {
        guard trace else { return }
        FileHandle.standardError.write(Data("hooksrv: \(message())\n".utf8))
    }

    /// Same, but says which socket is speaking. Two servers in one test run
    /// are indistinguishable otherwise.
    private func note(_ message: @autoclosure () -> String) {
        Self.note("[\((path as NSString).lastPathComponent)] \(message())")
    }

    private func acceptOne() async {
        guard listening >= 0 else {
            note("acceptOne : plus d'écoute")
            return
        }
        let fd = accept(listening, nil, nil)
        guard fd >= 0 else {
            note("accept → \(fd), errno \(errno)")
            return
        }
        note("accept → fd \(fd)")
        // Not inherited from the listening socket: each connection needs it.
        HookSocket.silencePipe(fd)
        // **And neither is a read deadline.** `readLine` blocks byte by byte
        // with no bound of its own, so a connection that never delivers a
        // complete line holds a descriptor and a GCD thread for the life of the
        // process. Observed while chasing RFC-006 T11: a trace showed `accept`
        // followed by nothing at all, for ever.
        //
        // Whatever makes that happen, waiting for ever cannot be the answer in
        // an app whose first rule is never to block. Ten seconds is far beyond
        // any real hook — `vibe-hook` writes its line and exits — and turns an
        // indefinite hang into a closed socket.
        HookSocket.setReadTimeout(fd, seconds: 10)
        open.insert(fd)
        let pid = HookSocket.peerPID(fd)

        // Off the actor: `readLine` blocks, and the actor must stay free to
        // accept the next hook — Claude Code spawns them in bursts.
        let line = await Self.read(fd)
        note("read fd \(fd) → \(line.map { "\($0.count) octets" } ?? "nil")")
        guard let line, let request = HookLine.decodeRequest(line) else {
            note("fd \(fd) : ligne illisible, abandon")
            finish(fd); return
        }

        guard request.event.isBlocking else {
            note("fd \(fd) : \(request.event.rawValue) en tir-et-oublie")
            // Fire-and-forget. Close first: the hook has already exited, and
            // holding the descriptor open buys nothing.
            finish(fd)
            _ = await sink.handle(request, from: pid)
            return
        }

        let decision = await withTaskGroup(of: HookDecision?.self) { group in
            group.addTask { await self.sink.handle(request, from: pid) }
            // The user may answer in the terminal instead. Claude Code then
            // kills the hook, and this is the only thing that says so.
            group.addTask { await Self.waitForHangUp(fd) }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        if let decision, let reply = try? HookLine.encodeDecision(decision) {
            _ = HookSocket.write(reply, to: fd)
        }
        finish(fd)
    }

    private func finish(_ fd: Int32) {
        open.remove(fd)
        close(fd)
    }

    // MARK: - Off-actor waits

    private static func read(_ fd: Int32) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: HookSocket.readLine(from: fd))
            }
        }
    }

    /// Resolves to `nil` when the peer goes away — and when the task is
    /// cancelled, which is the case that matters.
    ///
    /// A `DispatchSource` rather than a poll: the descriptor becomes readable
    /// when the peer hangs up, so this costs nothing until it happens. But it
    /// **must** honour cancellation: leaving `withTaskGroup` waits for every
    /// child, so a continuation that only ever resumes on hang-up deadlocks the
    /// server the moment the sink answers first.
    private static func waitForHangUp(_ fd: Int32) async -> HookDecision? {
        let box = OnceBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.arm(continuation)
                let source = DispatchSource.makeReadSource(
                    fileDescriptor: fd, queue: .global(qos: .utility))
                box.hold(source)
                source.setEventHandler {
                    guard HookSocket.peerHungUp(fd) else { return }
                    box.fire()
                }
                source.resume()
            }
        } onCancel: {
            box.fire()
        }
    }
}

/// Resumes a continuation exactly once, and cancels the source that feeds it.
///
/// A `DispatchSource` handler can fire again between `cancel()` and the cancel
/// taking effect, and cancellation can arrive before the continuation is even
/// armed. Resuming twice is a crash, not a warning.
private final class OnceBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<HookDecision?, Never>?
    private var source: DispatchSourceRead?
    private var spent = false
    private let lock = NSLock()

    func arm(_ continuation: CheckedContinuation<HookDecision?, Never>) {
        lock.lock()
        if spent {
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func hold(_ source: DispatchSourceRead) {
        lock.lock(); defer { lock.unlock() }
        self.source = source
    }

    func fire() {
        lock.lock()
        let pending = continuation
        let held = source
        continuation = nil
        source = nil
        spent = true
        lock.unlock()
        held?.cancel()
        pending?.resume(returning: nil)
    }
}
