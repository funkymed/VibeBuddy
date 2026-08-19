import Testing
import Foundation
@testable import NotchBuddyKit

/// End-to-end: real transcript files on disk, through `SessionStore`, into
/// `AlertTracker`, out as alerts.
///
/// This exists because the path cannot be verified by hand. Watching it from
/// inside a live session fails twice over: the observing session is itself busy
/// running the check, so it never looks finished; and its terminal is frontmost,
/// so the policy correctly suppresses anything that did fire. Both behaviours
/// are right, and together they make manual verification impossible.
///
/// Hence a temporary project root and an injected liveness source.
@Suite("Alert pipeline", .serialized)
@MainActor
struct AlertPipelineTests {

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchbuddy-pipeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Write a transcript for `project` in the fake root.
    @discardableResult
    private func write(_ root: URL, project: String, session: String, entries: [String]) throws -> String {
        let dir = root.appendingPathComponent("-Users-dev-\(project)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(session).jsonl")
        try Data(entries.joined(separator: "\n").utf8).write(to: file)
        return file.path
    }

    private func working(cwd: String, session: String) -> [String] {
        [
            #"{"type":"user","sessionId":"\#(session)","cwd":"\#(cwd)","timestamp":"2026-08-19T16:00:00.000Z"}"#,
            #"{"type":"assistant","sessionId":"\#(session)","cwd":"\#(cwd)","timestamp":"2026-08-19T16:00:01.000Z","message":{"model":"claude-opus-5","content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build"}}]}}"#,
        ]
    }

    private func finished(cwd: String, session: String, error: Bool = false) -> [String] {
        [
            #"{"type":"user","sessionId":"\#(session)","cwd":"\#(cwd)","timestamp":"2026-08-19T16:00:02.000Z","message":{"content":[{"type":"tool_result","is_error":\#(error),"content":"x"}]}}"#,
            #"{"type":"system","subtype":"turn_duration","durationMs":1200,"sessionId":"\#(session)","cwd":"\#(cwd)","timestamp":"2026-08-19T16:00:03.000Z"}"#,
        ]
    }

    @Test("a session that finishes while alive produces exactly one alert")
    func finishingAlerts() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cwd = "/Users/dev/notch"
        try write(root, project: "notch", session: "s1", entries: working(cwd: cwd, session: "s1"))

        let store = SessionStore(root: root.path, liveness: { [cwd: [4242]] })
        let bus = AlertBus()
        let tracker = AlertTracker(bus: bus)

        var sessions = await store.refresh()
        #expect(sessions.first?.isLive == true)
        #expect(tracker.ingest(sessions).isEmpty, "working must not alert")

        try write(root, project: "notch", session: "s1",
                  entries: working(cwd: cwd, session: "s1") + finished(cwd: cwd, session: "s1"))
        sessions = await store.refresh()
        let alerts = tracker.ingest(sessions)

        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .finished)
        #expect(alerts.first?.projectName == "notch")
        #expect(bus.delivered.count == 1)
    }

    @Test("a turn that ended in error reports failure")
    func failingAlerts() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cwd = "/Users/dev/hykaro"
        try write(root, project: "hykaro", session: "s2", entries: working(cwd: cwd, session: "s2"))

        let store = SessionStore(root: root.path, liveness: { [cwd: [4243]] })
        let tracker = AlertTracker(bus: AlertBus())
        _ = tracker.ingest(await store.refresh())

        try write(root, project: "hykaro", session: "s2",
                  entries: working(cwd: cwd, session: "s2")
                      + finished(cwd: cwd, session: "s2", error: true))
        let alerts = tracker.ingest(await store.refresh())
        #expect(alerts.first?.kind == .failed)
    }

    // The reason to watch more than one agent at all: three finishing in three
    // projects must produce three attributed alerts, not one.
    @Test("three projects finishing are three attributed alerts")
    func threeProjects() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ["notch", "hykaro", "tigreboite"]
        var live: [String: [pid_t]] = [:]

        for (i, project) in projects.enumerated() {
            let cwd = "/Users/dev/\(project)"
            live[cwd] = [pid_t(5000 + i)]
            try write(root, project: project, session: "s\(i)",
                      entries: working(cwd: cwd, session: "s\(i)"))
        }

        let snapshot = live
        let store = SessionStore(root: root.path, liveness: { snapshot })
        let tracker = AlertTracker(bus: AlertBus())
        _ = tracker.ingest(await store.refresh())

        for (i, project) in projects.enumerated() {
            let cwd = "/Users/dev/\(project)"
            try write(root, project: project, session: "s\(i)",
                      entries: working(cwd: cwd, session: "s\(i)")
                          + finished(cwd: cwd, session: "s\(i)"))
        }

        // The rate limiter deliberately collapses a simultaneous burst, so the
        // states are asserted rather than the deliveries — three sessions must
        // each be recognised as finished even when only one interruption is shown.
        let sessions = await store.refresh()
        let published = tracker.ingest(sessions)
        #expect(sessions.count == 3)
        for (i, _) in projects.enumerated() {
            #expect(tracker.state(of: "s\(i)") == .finished)
        }
        #expect(published.count + tracker.suppressed.count == 3)
        #expect(published.count == 1, "a simultaneous burst is one interruption")
    }

    // A dead session must stay silent: the process is gone, so the user already
    // knows. Without this, restarting the app would re-alert every old transcript.
    @Test("a finished transcript with no live process alerts nothing")
    func deadSessionSilent() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cwd = "/Users/dev/ghost"
        try write(root, project: "ghost", session: "s9",
                  entries: working(cwd: cwd, session: "s9") + finished(cwd: cwd, session: "s9"))

        let store = SessionStore(root: root.path, liveness: { [:] })   // nothing running
        let tracker = AlertTracker(bus: AlertBus())
        let alerts = tracker.ingest(await store.refresh())
        #expect(alerts.isEmpty)
    }
}
