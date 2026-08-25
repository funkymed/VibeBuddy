import Testing
import Foundation
@testable import VibeBuddyKit

private enum TimelineFixtures {
    static func line(_ json: String) -> String { json }

    static let prompt = #"""
    {"type":"user","uuid":"u1","timestamp":"2026-08-25T10:00:00.000Z","message":{"role":"user","content":"Corrige le parseur"}}
    """#

    static let toolUse = #"""
    {"type":"assistant","uuid":"a1","timestamp":"2026-08-25T10:00:01.000Z","message":{"model":"claude-opus-5","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift build"}}]}}
    """#

    /// A `tool_result` arrives as a `user` entry, never as a type of its own.
    static let toolResult = #"""
    {"type":"user","uuid":"u2","timestamp":"2026-08-25T10:00:02.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"boom"}]}}
    """#

    static let turnEnd = #"""
    {"type":"system","uuid":"s1","subtype":"turn_duration","durationMs":12345,"timestamp":"2026-08-25T10:00:03.000Z"}
    """#

    static let subagents = #"""
    {"type":"started","uuid":"g1","timestamp":"2026-08-25T10:00:04.000Z","description":"auditer les fiches"}
    {"type":"result","uuid":"g2","timestamp":"2026-08-25T10:00:05.000Z"}
    """#

    static var whole: Data {
        [prompt, toolUse, toolResult, turnEnd, subagents]
            .joined(separator: "\n").data(using: .utf8)!
    }
}

@Suite("Session timeline parsing")
struct SessionTimelineParserTests {
    @Test("every kind of entry becomes one event, in the order it was written")
    func kinds() {
        let events = TimelineParser.parse(TimelineFixtures.whole)
        #expect(events.count == 6)
        #expect(events[0].kind == .prompt)
        #expect(events[1].kind == .tool(.shell))
        #expect(events[2].kind == .result(failed: true))
        #expect(events[3].kind == .turnEnd(milliseconds: 12345))
        #expect(events[4].kind == .subagentStarted)
        #expect(events[5].kind == .subagentFinished)
    }

    @Test("a tool carries what it was pointed at")
    func subject() {
        let events = TimelineParser.parse(TimelineFixtures.whole)
        #expect(events[1].text == "swift build")
    }

    @Test("a prompt keeps its text and its timestamp")
    func promptText() {
        let events = TimelineParser.parse(TimelineFixtures.whole)
        #expect(events[0].text == "Corrige le parseur")
        #expect(events[0].at != nil)
    }

    // A tool_result is a `user` entry: keying on the entry type alone reads it as a
    // prompt, and the timeline then shows the user typing after every tool call.
    @Test("a tool_result is never read as a prompt")
    func resultIsNotAPrompt() {
        let events = TimelineParser.parse(TimelineFixtures.whole)
        #expect(!events.contains { $0.kind == .prompt && $0.id.hasPrefix("u2") })
    }

    @Test("text is flattened and clipped at parse time")
    func clipping() {
        let long = String(repeating: "a", count: TimelineParser.maxTextLength + 50)
        #expect(TimelineParser.clip("deux\nlignes") == "deux lignes")
        #expect(TimelineParser.clip(long).count == TimelineParser.maxTextLength + 1)
    }

    @Test("only the newest events are kept")
    func cap() {
        let many = Array(repeating: TimelineFixtures.prompt, count: TimelineParser.maxEvents + 20)
            .joined(separator: "\n").data(using: .utf8)!
        #expect(TimelineParser.parse(many).count == TimelineParser.maxEvents)
    }

    @Test("a truncated line is skipped rather than throwing the read away")
    func partialLine() {
        let broken = ("{\"type\":\"user\",\"message\":{\"content\":\"coup" + "\n"
            + TimelineFixtures.toolUse).data(using: .utf8)!
        #expect(TimelineParser.parse(broken).count == 1)
    }

    @Test("an empty transcript is empty, not nil")
    func empty() {
        #expect(TimelineParser.parse(Data()).isEmpty)
    }
}

@Suite("Session timeline loader")
struct SessionTimelineLoaderTests {
    private func write(_ data: Data) throws -> String {
        let path = NSTemporaryDirectory() + "vb-timeline-\(UUID().uuidString).jsonl"
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test("reads a transcript from disk")
    func reads() async throws {
        let path = try write(TimelineFixtures.whole)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let loader = SessionTimelineLoader()
        let events = await loader.events(at: path)
        #expect(events?.count == 6)
    }

    @Test("an unreadable path is nil, which an empty session is not")
    func missing() async {
        let loader = SessionTimelineLoader()
        #expect(await loader.events(at: "/nowhere/at/all.jsonl") == nil)
    }

    @Test("a second read of an unchanged file does not parse again")
    func caches() async throws {
        let path = try write(TimelineFixtures.whole)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let loader = SessionTimelineLoader()
        _ = await loader.events(at: path)
        _ = await loader.events(at: path)
        #expect(await loader.cachedCount == 1)
    }

    // Keyed on mtime and size both: a rewrite can keep the size, and a file can change
    // size inside the same second.
    @Test("a changed file is read again")
    func invalidates() async throws {
        let path = try write(TimelineFixtures.prompt.data(using: .utf8)!)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let loader = SessionTimelineLoader()
        #expect(await loader.events(at: path)?.count == 1)

        try TimelineFixtures.whole.write(to: URL(fileURLWithPath: path))
        #expect(await loader.events(at: path)?.count == 6)
    }

    @Test("eviction keeps only what is asked for")
    func evicts() async throws {
        let a = try write(TimelineFixtures.whole)
        let b = try write(TimelineFixtures.whole)
        defer {
            try? FileManager.default.removeItem(atPath: a)
            try? FileManager.default.removeItem(atPath: b)
        }
        let loader = SessionTimelineLoader()
        _ = await loader.events(at: a)
        _ = await loader.events(at: b)
        await loader.evict(keeping: [a])
        #expect(await loader.cachedCount == 1)
    }
}
