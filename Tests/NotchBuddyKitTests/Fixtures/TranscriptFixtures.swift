import Foundation

/// Synthetic transcripts mirroring Claude Code 2.1.234's real shape.
///
/// Hand-written rather than captured, so they carry no conversation content and
/// can be read, diffed and extended. Every entry type here was observed in a
/// real transcript on 2026-08-19.
enum TranscriptFixtures {

    static func data(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    static let cwd = "/Users/dev/Sites/notch"
    static let sessionID = "82f4eebc-6d77-490e-a662-c231bf80f582"

    static func base(_ type: String, _ extra: String = "") -> String {
        """
        {"type":"\(type)","sessionId":"\(sessionID)","cwd":"\(cwd)",\
        "version":"2.1.234","gitBranch":"feat/rfc-003",\
        "timestamp":"2026-08-19T16:33:49.396Z"\(extra.isEmpty ? "" : ",\(extra)")}
        """
    }

    /// Agent is running a shell command.
    static let runningShell = data([
        base("user"),
        base("assistant", """
        "message":{"model":"claude-opus-5","usage":{"input_tokens":1200,\
        "cache_read_input_tokens":48000,"cache_creation_input_tokens":800,"output_tokens":90},\
        "content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build"}}]}
        """),
    ])

    /// Agent ran something destructive.
    static let runningDanger = data([
        base("assistant", """
        "message":{"model":"claude-opus-5","usage":{"input_tokens":10,\
        "cache_read_input_tokens":0,"cache_creation_input_tokens":0},\
        "content":[{"type":"tool_use","name":"Bash","input":{"command":"sudo rm -rf /var"}}]}
        """),
    ])

    /// Turn finished — the signal the reference implementation takes from a hook.
    static let turnFinished = data([
        base("assistant", """
        "message":{"model":"claude-opus-5","usage":{"input_tokens":500,\
        "cache_read_input_tokens":120000,"cache_creation_input_tokens":0},\
        "content":[{"type":"text","text":"done"}]}
        """),
        """
        {"type":"system","subtype":"stop_hook_summary","hookCount":1,\
        "preventedContinuation":false,"stopReason":"",\
        "timestamp":"2026-08-19T16:33:49.396Z","session_id":"\(sessionID)"}
        """,
        """
        {"type":"system","subtype":"turn_duration","durationMs":3322,"messageCount":9,\
        "timestamp":"2026-08-19T16:33:49.396Z","sessionId":"\(sessionID)",\
        "cwd":"\(cwd)","version":"2.1.234","gitBranch":"feat/rfc-003"}
        """,
    ])

    /// The permission mode lives in the transcript, in two shapes.
    static let permissionModeEntry = data([
        base("assistant", "\"message\":{\"model\":\"claude-opus-5\"}"),
        """
        {"type":"permission-mode","permissionMode":"auto","sessionId":"\(sessionID)"}
        """,
    ])

    static let permissionModeInline = data([
        base("user", "\"permissionMode\":\"plan\""),
    ])

    /// Entry types that exist and carry nothing we need.
    static let noiseOnly = data([
        base("attachment"),
        base("file-history-snapshot"),
        """
        {"type":"last-prompt","lastPrompt":"hello","sessionId":"\(sessionID)"}
        """,
        """
        {"type":"mode","mode":"normal","sessionId":"\(sessionID)"}
        """,
        """
        {"type":"queue-operation","operation":"enqueue","content":"next",\
        "sessionId":"\(sessionID)","timestamp":"2026-08-19T16:38:27.445Z"}
        """,
    ])

    /// A tool result that came back as an error.
    static let toolError = data([
        base("assistant", #""message":{"model":"claude-opus-5","content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build"}}]}"#),
        base("user", #""message":{"content":[{"type":"tool_result","is_error":true,"content":"error: cannot find type"}]}"#),
    ])

    /// A successful tool result.
    static let toolSuccess = data([
        base("user", #""message":{"content":[{"type":"tool_result","is_error":false,"content":"ok"}]}"#),
    ])

    /// Each tool puts its subject under a different key.
    static func toolUse(_ name: String, _ inputJSON: String) -> Data {
        data([base("assistant",
            #""message":{"model":"claude-opus-5","content":[{"type":"tool_use","name":"#
            + "\"\(name)\"" + #","input":"# + inputJSON + "}]}")])
    }

    /// Subagent lifecycle: two started, one finished.
    static let subagents = data([
        base("assistant", "\"message\":{\"model\":\"claude-opus-5\"}"),
        #"{"type":"started","key":"v2:aaa","agentId":"a92c0c13dfc397e99"}"#,
        #"{"type":"started","key":"v2:bbb","agentId":"ae8cbdca3fbae9a12"}"#,
        #"{"type":"result","key":"v2:aaa","agentId":"a92c0c13dfc397e99","result":"done"}"#,
    ])

    /// A type the parser has never seen — the R9 case.
    static let unknownType = data([
        base("assistant", "\"message\":{\"model\":\"claude-opus-5\"}"),
        """
        {"type":"some-future-thing","payload":42,"sessionId":"\(sessionID)"}
        """,
        """
        {"type":"some-future-thing","payload":43,"sessionId":"\(sessionID)"}
        """,
    ])

    /// A truncated final line, which is what a tail read produces mid-write.
    static let truncatedTail = data([
        base("assistant", """
        "message":{"model":"claude-opus-5",\
        "content":[{"type":"tool_use","name":"Read","input":{"file_path":"x"}}]}
        """),
        #"{"type":"assistant","message":{"mod"#,
    ])
}
