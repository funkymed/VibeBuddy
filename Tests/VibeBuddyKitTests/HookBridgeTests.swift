import Foundation
import Testing
@testable import VibeBuddyKit
@testable import VibeHookProtocol

/// The repository root, from this file's own path.
private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

@Suite("Hook: the response schema")
struct HookSchemaTests {

    /// R6 in one assertion. Claude Code invalidates the whole response if a
    /// single extra top-level field appears, silently, and falls back to its own
    /// prompt — the user sees the normal prompt and concludes the app is broken.
    @Test("allow encodes to exactly these bytes, and nothing else")
    func allowIsByteExact() throws {
        let data = try HookWire.encode(.allow)
        let expected = #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#
        #expect(String(data: data, encoding: .utf8) == expected)
    }

    @Test("deny carries its message and nothing more")
    func denyIsByteExact() throws {
        let data = try HookWire.encode(.deny(message: "REFUS-SPIKE-7f3a"))
        let expected = #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"REFUS-SPIKE-7f3a"},"hookEventName":"PermissionRequest"}}"#
        #expect(String(data: data, encoding: .utf8) == expected)
    }

    @Test("the top level holds one key, and the decision holds only its own")
    func noStrayFields() throws {
        for decision in [HookDecision.allow, .deny(message: "non")] {
            let object = try JSONSerialization.jsonObject(
                with: HookWire.encode(decision)) as? [String: Any]
            let top = try #require(object)
            #expect(Array(top.keys) == ["hookSpecificOutput"])
            let inner = try #require(top["hookSpecificOutput"] as? [String: Any])
            #expect(Set(inner.keys) == ["hookEventName", "decision"])
            let body = try #require(inner["decision"] as? [String: Any])
            let allowed: Set<String> = decision == .allow ? ["behavior"] : ["behavior", "message"]
            #expect(Set(body.keys) == allowed)
        }
    }

    @Test("only PermissionRequest blocks")
    func onlyOneBlocks() {
        for event in HookEventName.allCases {
            #expect(event.isBlocking == (event == .permissionRequest), "\(event)")
        }
    }
}

@Suite("Hook: what arrives on stdin")
struct HookRequestTests {

    @Test("a real payload parses, and the raw bytes are kept")
    func parsesPayload() throws {
        let stdin = Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#.utf8)
        let request = try #require(HookRequest.parse(stdin))
        #expect(request.event == .permissionRequest)
        // Kept whole rather than decoded field by field: every field the hook
        // learns to read is a field it can break on when Claude Code adds one.
        #expect(request.payload == stdin)
    }

    @Test("anything unexpected parses to nothing", arguments: [
        "", "pas du json", "[]", "{}", #"{"hook_event_name":"Inconnu"}"#,
        #"{"hook_event_name":123}"#, "null",
    ])
    func rejectsJunk(_ text: String) {
        #expect(HookRequest.parse(Data(text.utf8)) == nil)
    }

    @Test("the line protocol round-trips a request")
    func requestRoundTrip() throws {
        let stdin = Data(#"{"hook_event_name":"Stop","session_id":"abc"}"#.utf8)
        let request = try #require(HookRequest.parse(stdin))
        var line = try HookLine.encodeRequest(request)
        #expect(line.last == 0x0A, "la trame est une ligne")
        line.removeLast()
        let back = try #require(HookLine.decodeRequest(line))
        #expect(back.event == .stop)
        #expect(try JSONSerialization.jsonObject(with: back.payload) is [String: Any])
    }

    @Test("the line protocol round-trips a decision")
    func decisionRoundTrip() throws {
        for decision in [HookDecision.allow, .deny(message: "pas ça")] {
            var line = try HookLine.encodeDecision(decision)
            line.removeLast()
            #expect(HookLine.decodeDecision(line) == decision)
        }
    }

    @Test("a line from another version is refused rather than guessed")
    func versionIsChecked() throws {
        let line = Data(#"{"v":99,"event":"Stop","payload":{}}"#.utf8)
        #expect(HookLine.decodeRequest(line) == nil)
    }
}

@Suite("Hook: the binary links no UI")
struct HookIsForbiddenAppKitTests {

    /// D4, enforced. dyld loads what this binary links **before** `main` runs,
    /// on every tool call of every session. The reference implementation pays
    /// 40-60 ms there; the budget for this one is 8.
    @Test("neither the hook nor its protocol imports AppKit or SwiftUI")
    func noUIImports() throws {
        for directory in ["Sources/VibeHook", "Sources/VibeHookProtocol"] {
            let root = repositoryRoot.appendingPathComponent(directory)
            let files = try FileManager.default
                .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            #expect(!files.isEmpty, "\(directory) est vide")
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for banned in ["import AppKit", "import SwiftUI", "import VibeBuddyKit"] {
                    #expect(!text.contains(banned), "\(file.lastPathComponent) : \(banned)")
                }
            }
        }
    }
}

/// Records what the app was told, and answers what the test tells it to.
private final class RecordingSink: HookEventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [HookRequest] = []
    private let answer: HookDecision?
    /// Held before answering, to model a user who is still thinking.
    private let delay: TimeInterval

    init(answer: HookDecision? = .allow, delay: TimeInterval = 0) {
        self.answer = answer
        self.delay = delay
    }

    var received: [HookRequest] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    func handle(_ request: HookRequest, from pid: pid_t?) async -> HookDecision? {
        record(request)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
        return answer
    }

    /// Outside the async context: `NSLock` is unavailable there, and holding a
    /// lock across a suspension point is how you deadlock an actor anyway.
    private func record(_ request: HookRequest) {
        lock.lock(); defer { lock.unlock() }
        seen.append(request)
    }
}

/// Short on purpose: `sun_path` holds 103 bytes, and the system temp directory
/// alone is longer than that.
private func temporarySocket() -> String {
    "/tmp/vb-\(UUID().uuidString.prefix(8)).sock"
}

private func send(_ json: String, to path: String, expectingReply: Bool) -> String? {
    guard let fd = try? HookSocket.connect(to: path, timeout: 5) else { return nil }
    defer { close(fd) }
    guard let request = HookRequest.parse(Data(json.utf8)),
          let line = try? HookLine.encodeRequest(request),
          HookSocket.write(line, to: fd)
    else { return nil }
    guard expectingReply else { return "" }
    guard let reply = HookSocket.readLine(from: fd) else { return nil }
    return String(data: reply, encoding: .utf8)
}

@Suite("Hook: the socket, end to end")
struct HookSocketServerTests {

    @Test("a fire-and-forget event reaches the app")
    func nonBlockingArrives() async throws {
        let sink = RecordingSink()
        let server = HookSocketServer(path: temporarySocket(), sink: sink)
        try await server.start()
        defer { Task { await server.stop() } }

        let path = await server.socketPath
        #expect(send(#"{"hook_event_name":"Stop","session_id":"s1"}"#,
                     to: path, expectingReply: false) == "")
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(sink.received.map(\.event) == [.stop])
    }

    @Test("a permission request gets its decision back")
    func blockingIsAnswered() async throws {
        let sink = RecordingSink(answer: .deny(message: "non merci"))
        let server = HookSocketServer(path: temporarySocket(), sink: sink)
        try await server.start()
        defer { Task { await server.stop() } }

        let path = await server.socketPath
        let reply = send(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#,
                         to: path, expectingReply: true)
        let line = try #require(reply)
        #expect(HookLine.decodeDecision(Data(line.utf8)) == .deny(message: "non merci"))
        #expect(sink.received.first?.event == .permissionRequest)
    }

    /// The user answered in the terminal, so Claude Code killed the hook. The
    /// app has to notice: otherwise the notch keeps showing a prompt for a
    /// decision nobody is waiting for any more.
    @Test("hanging up mid-decision does not wedge the server")
    func peerHangUpIsNoticed() async throws {
        let sink = RecordingSink(answer: .allow, delay: 30)
        let server = HookSocketServer(path: temporarySocket(), sink: sink)
        try await server.start()
        defer { Task { await server.stop() } }
        let path = await server.socketPath

        let fd = try HookSocket.connect(to: path, timeout: 5)
        let request = try #require(HookRequest.parse(
            Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#.utf8)))
        #expect(HookSocket.write(try HookLine.encodeRequest(request), to: fd))
        try await Task.sleep(nanoseconds: 200_000_000)
        close(fd)

        // The sink is still asleep for thirty seconds; the connection must be
        // released anyway, and the next hook must be served.
        try await Task.sleep(nanoseconds: 600_000_000)
        let after = HookSocketServer(path: temporarySocket(), sink: RecordingSink())
        try await after.start()
        let second = await after.socketPath
        #expect(send(#"{"hook_event_name":"Stop"}"#, to: second, expectingReply: false) == "")
        await after.stop()
    }

    @Test("the socket is private to its owner, and survives a stale file")
    func socketIsPrivate() async throws {
        let path = temporarySocket()
        FileManager.default.createFile(atPath: path, contents: Data("résidu".utf8))

        let server = HookSocketServer(path: path, sink: RecordingSink())
        // Binding over a leftover file is the normal case after a crash: the
        // stale socket is unlinked rather than left to fail with EADDRINUSE.
        try await server.start()
        defer { Task { await server.stop() } }

        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600, "mode \(String(mode ?? -1, radix: 8))")
    }

    @Test("stopping releases the socket file")
    func stopUnlinks() async throws {
        let path = temporarySocket()
        let server = HookSocketServer(path: path, sink: RecordingSink())
        try await server.start()
        #expect(FileManager.default.fileExists(atPath: path))
        await server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("a path longer than sun_path is refused, not truncated")
    func pathLimitIsEnforced() async {
        let long = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        let server = HookSocketServer(path: long, sink: RecordingSink())
        await #expect(throws: HookSocket.Failure.pathTooLong) { try await server.start() }
    }
}
