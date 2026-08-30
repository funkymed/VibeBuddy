import Darwin
import Foundation
import VibeHookProtocol

/// What the app does with an event the hook forwarded.
public protocol HookEventSink: Sendable {
    func handle(_ request: HookRequest, from pid: pid_t?) async -> HookDecision?
}

/// Listens on the Unix socket the `vibe-hook` binary connects to.
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

    /// Set `VIBEBUDDY_HOOK_TRACE` to see which call returned what, in order.
    private static let trace = ProcessInfo.processInfo.environment["VIBEBUDDY_HOOK_TRACE"] != nil

    private static func note(_ message: @autoclosure () -> String) {
        guard trace else { return }
        FileHandle.standardError.write(Data("hooksrv: \(message())\n".utf8))
    }

    /// Same, but says which socket is speaking.
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
        // And neither is a read deadline. `readLine` blocks byte by byte with no
        // bound of its own, so a connection that never delivers a complete line holds a
        // descriptor and a GCD thread for the life of the process.
        HookSocket.setReadTimeout(fd, seconds: 10)
        open.insert(fd)
        let pid = HookSocket.peerPID(fd)

        // Off the actor: `readLine` blocks, and the actor must stay free to accept the
        // next hook — Claude Code spawns them in bursts.
        let line = await Self.read(fd)
        note("read fd \(fd) → \(line.map { "\($0.count) octets" } ?? "nil")")
        guard let line, let request = HookLine.decodeRequest(line) else {
            note("fd \(fd) : ligne illisible, abandon")
            finish(fd); return
        }

        guard request.event.isBlocking else {
            note("fd \(fd) : \(request.event.rawValue) en tir-et-oublie")
            // Fire-and-forget.
            finish(fd)
            _ = await sink.handle(request, from: pid)
            return
        }

        enum Outcome: Sendable { case decided(HookDecision?), hungUp }

        let decision = await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .decided(await self.sink.handle(request, from: pid)) }
            // The user may answer in the terminal instead.
            group.addTask {
                _ = await Self.waitForHangUp(fd)
                return .hungUp
            }

            // The sink always wins the race. A decision is information, a hang-up is an
            // absence, and `group.next()` hands back whichever finished first — which is
            // the hang-up on one request in three. Writing into a socket whose peer has
            // really gone costs nothing (`SO_NOSIGPIPE` is set on every accepted
            // descriptor); not writing while someone waits costs Claude Code 120 s.
            var answer: HookDecision?
            while let outcome = await group.next() {
                guard case let .decided(value) = outcome else { continue }
                answer = value
                break
            }
            group.cancelAll()
            return answer
        }

        if let decision, let reply = try? HookLine.encodeDecision(decision) {
            _ = HookSocket.write(reply, to: fd)
        }
        finish(fd)
    }

    private func finish(_ fd: Int32) {
        guard open.remove(fd) != nil else { return }
        close(fd)
    }

    private static func read(_ fd: Int32) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: HookSocket.readLine(from: fd))
            }
        }
    }

    /// Resolves to `nil` when the peer goes away — and when the task is cancelled, which
    /// is the case that matters.
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
