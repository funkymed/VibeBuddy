import Foundation
import Testing
@testable import VibeBuddyKit

@Suite("The tongue under the notch")
struct AlertStackTests {
    private func alert(_ session: String, _ kind: SessionAlert.Kind, _ seconds: TimeInterval) -> SessionAlert {
        SessionAlert(sessionID: session, projectName: session, kind: kind,
                     at: Date(timeIntervalSince1970: seconds))
    }

    private func session(_ id: String, live: Bool = true, turnEnded: Bool = false,
                         error: Bool = false, awaiting: Bool = false,
                         action: ToolAction = .none) -> AgentSession {
        AgentSession(id: id, cwd: "/tmp/\(id)", projectName: id, model: "", startedAt: .now,
                     lastActivity: .now, status: nil, action: action, permissionMode: "",
                     contextTokens: 0, contextWindow: 0, pid: live ? 1 : nil, isLive: live,
                     turnEnded: turnEnded, lastResultWasError: error, awaitingAnswer: awaiting)
    }

    @Test("waiting beats failing beats finishing, whatever the order they came in")
    func urgency() {
        var stack = AlertStack()
        stack.push(alert("a", .finished, 3))
        stack.push(alert("b", .failed, 1))
        #expect(stack.head?.sessionID == "b")
        stack.push(alert("c", .needsAttention, 0))
        #expect(stack.head?.sessionID == "c")
        #expect(stack.count == 3)
    }

    @Test("same urgency: the newest leads")
    func newestLeads() {
        var stack = AlertStack()
        stack.push(alert("a", .finished, 1))
        stack.push(alert("b", .finished, 2))
        #expect(stack.head?.sessionID == "b")
    }

    @Test("a session has one entry, its latest")
    func oneEntryPerSession() {
        var stack = AlertStack()
        stack.push(alert("a", .failed, 1))
        stack.push(alert("a", .finished, 2))
        #expect(stack.count == 1)
        #expect(stack.head?.kind == .finished)
    }

    // A session that has started its next turn has made its alert stale.
    @Test("a live session that moved on drops its entry")
    func pruneMovedOn() {
        var stack = AlertStack()
        stack.push(alert("a", .finished, 1))
        stack.push(alert("b", .failed, 1))
        stack.prune(against: [session("a", action: .shell),
                              session("b", turnEnded: true, error: true)])
        #expect(stack.entries.map(\.sessionID) == ["b"])
    }

    // Finished, then exited before anyone looked: still news.
    @Test("a session that ended or vanished keeps its entry")
    func pruneKeepsTheGone() {
        var stack = AlertStack()
        stack.push(alert("a", .finished, 1))
        stack.push(alert("b", .finished, 1))
        stack.prune(against: [session("a", live: false)])
        #expect(stack.count == 2)
    }

    @Test("an unanswered question stays while it is unanswered")
    func pruneAwaiting() {
        var stack = AlertStack()
        stack.push(alert("a", .needsAttention, 1))
        stack.prune(against: [session("a", awaiting: true)])
        #expect(stack.count == 1)
        stack.prune(against: [session("a", action: .editing)])
        #expect(stack.isEmpty)
    }

    @Test("each kind has its glyph, and each glyph the colour of a face")
    func glyphs() {
        #expect(AlertGlyph(.finished) == .check)
        #expect(AlertGlyph(.failed) == .cross)
        #expect(AlertGlyph(.needsAttention) == .question)
        #expect(AlertGlyph.question.expression == .awaiting)
    }

    // Six rows at the buddy's pitch: 18 pt inside a 26 pt tongue.
    @Test("glyphs are six cells tall, rectangular, lit, and distinct", arguments: AlertGlyph.allCases)
    func bitmaps(_ glyph: AlertGlyph) {
        #expect(glyph.rows == 6)
        #expect(Set(glyph.bitmap.map(\.count)).count == 1, "lignes de longueurs différentes")
        let cells = glyph.cells(pitch: 3)
        #expect(!cells.isEmpty)
        let size = glyph.size(pitch: 3)
        #expect(cells.allSatisfy { CGRect(origin: .zero, size: size).contains($0) })
        for other in AlertGlyph.allCases where other != glyph {
            #expect(other.bitmap != glyph.bitmap)
        }
    }
}
