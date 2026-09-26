import Foundation

/// Process death emits no filesystem event, so liveness stays a poll.
public actor SessionStore {
    public static let fullWalkInterval: TimeInterval = 120

    public static let staleAfter: TimeInterval = 15 * 60

    /// How long a session stays listed after its process is gone.
    public static let lingerAfterDeath: TimeInterval = 10

    /// Above this many prompt tokens the 1M window is *proved*. Backstop only — a
    /// session at 142k on 1M read 71 % instead of 14 % before `ContextWindowResolver`.
    public static let largeContextThreshold = 200_000
    public static let largeContextWindow = ContextWindowResolver.largeWindow

    private let root: String
    private let resolvedRoot: String
    private var reader = JSONLTailReader()

    private let liveness: @Sendable () -> [String: [pid_t]]

    /// Sticky: a tail landing on a user turn carries no `usage`, and the gauge would
    /// otherwise drop to zero and back on alternate reads.
    private var stickyTokens: [String: Int] = [:]
    /// Sessions never shrink back; flip-flopping the denominator makes the gauge jump.
    private var stickyWindow: [String: Int] = [:]
    private var windows = ContextWindowResolver()
    private var modes = PermissionModeResolver()
    /// Sticky like the token count, and for the same reason: the tail is 80 lines, and a
    /// long tool run pushes the last `permission-mode` entry out of it.
    private var stickyMode: [String: String] = [:]

    /// Sticky for the same reason as the mode: a parent that keeps talking while its
    /// workflow runs pushes the launch out of the 80-line tail.
    private var pendingTasks: [String: [String: Bool]] = [:]
    /// Transcripts kept past `staleAfter`: a parent waiting on a workflow writes
    /// nothing for as long as the workflow runs.
    private var busyPaths: Set<String> = []

    private var current: [AgentSession] = []

    public init(
        root: String? = nil,
        liveness: (@Sendable () -> [String: [pid_t]])? = nil
    ) {
        self.root = root
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        self.resolvedRoot = URL(fileURLWithPath: self.root).resolvingSymlinksInPath().path
        self.liveness = liveness ?? { ProcessLookup.agentPIDs() }
    }

    public var sessions: [AgentSession] { current }

    private var knownPaths: [String: (modified: Date, size: UInt64, created: Date)] = [:]
    private var lastFullWalk: Date = .distantPast

    /// `changed` is the FSEvents path list: re-stat only those, ~1 ms instead of ~17 ms
    /// on a 517-file corpus.
    @discardableResult
    public func refresh(now: Date = Date(), changed: [String]? = nil) -> [AgentSession] {
        let live = liveness()
        let candidates: [(path: String, tail: ParsedTail, modified: Date, created: Date)]
        if let changed, now.timeIntervalSince(lastFullWalk) < Self.fullWalkInterval {
            candidates = incremental(changed: changed, now: now)
        } else {
            candidates = transcripts(now: now)
            lastFullWalk = now
        }

        var sessions: [AgentSession] = []
        var seenPaths = Set<String>()

        var byCwd: [String: [(path: String, tail: ParsedTail, modified: Date, created: Date)]] = [:]
        for candidate in candidates {
            seenPaths.insert(candidate.path)
            guard let cwd = candidate.tail.cwd else { continue }
            byCwd[ProcessLookup.normalise(cwd), default: []].append(candidate)
        }

        for (cwd, group) in byCwd {
            let pids = live[cwd] ?? []
            // Freshest first, capped at the live process count: mtime lies about
            // liveness.
            let ranked = group.sorted { $0.modified > $1.modified }
            for (index, candidate) in ranked.enumerated() {
                let isLive = index < pids.count
                guard isLive || isFresh(candidate.path, candidate.modified, now) else { continue }
                sessions.append(makeSession(
                    candidate: candidate,
                    cwd: cwd,
                    // Positional pairing is a stopgap (risk R8): arbitrary when two
                    // agents share a directory.
                    pid: index < pids.count ? pids[index] : nil,
                    isLive: isLive
                ))
            }
        }

        let listed = Set(sessions.map(\.id))
        pendingTasks = pendingTasks.filter { listed.contains($0.key) }
        busyPaths.formIntersection(seenPaths)

        // Ten seconds after it stops, a session stops being news.
        sessions.removeAll {
            !$0.isLive && now.timeIntervalSince($0.lastActivity) >= Self.lingerAfterDeath
        }

        sessions.sort { $0.lastActivity > $1.lastActivity }
        reader.evict(keeping: seenPaths)

        if sessions != current { current = sessions }
        return sessions
    }

    private func makeSession(
        candidate: (path: String, tail: ParsedTail, modified: Date, created: Date),
        cwd: String, pid: pid_t?, isLive: Bool
    ) -> AgentSession {
        let id = (candidate.path as NSString).deletingPathExtension as NSString
        let sessionID = candidate.tail.sessionID ?? id.lastPathComponent
        let tail = candidate.tail

        if tail.contextTokens > 0 { stickyTokens[sessionID] = tail.contextTokens }
        let tokens = stickyTokens[sessionID] ?? 0
        if tokens > Self.largeContextThreshold { stickyWindow[sessionID] = Self.largeContextWindow }
        // They can only disagree one way — no session holds more than its window.
        let window = max(stickyWindow[sessionID] ?? 0, windows.window(forProject: cwd))

        // What the session says, then what it last said, then what the settings declare.
        // Empty only when no source has one, and the row keeps its column either way.
        if let seen = tail.permissionMode, !seen.isEmpty { stickyMode[sessionID] = seen }
        let mode = stickyMode[sessionID] ?? modes.mode(forProject: cwd)

        // A dead process takes its background tasks with it.
        var pending = isLive ? (pendingTasks[sessionID] ?? [:]) : [:]
        if isLive {
            pending.merge(tail.backgroundTasks) { $1 }
            for id in tail.reportedTasks { pending[id] = nil }
        }
        pendingTasks[sessionID] = pending.isEmpty ? nil : pending
        if pending.isEmpty { busyPaths.remove(candidate.path) } else { busyPaths.insert(candidate.path) }

        return AgentSession(
            id: sessionID,
            cwd: cwd,
            projectName: (cwd as NSString).lastPathComponent,
            model: tail.model ?? "",
            effort: tail.effort ?? "",
            startedAt: candidate.created,
            lastActivity: tail.lastTimestamp ?? candidate.modified,
            status: tail.turnEnded ? nil : tail.status,
            action: tail.action,
            permissionMode: mode,
            contextTokens: tokens,
            contextWindow: window,
            pid: pid,
            isLive: isLive,
            subject: tail.subject,
            turnEnded: tail.turnEnded,
            lastResultWasError: tail.lastResultWasError,
            // A workflow is subagents run elsewhere: same effect on the state.
            subagentsRunning: tail.subagentsRunning + pending.count,
            workflowsRunning: pending.values.filter { $0 }.count,
            awaitingAnswer: tail.awaitingQuestion,
            question: tail.question,
            transcriptPath: candidate.path
        )
    }

    private func incremental(changed: [String], now: Date)
        -> [(path: String, tail: ParsedTail, modified: Date, created: Date)] {
        for path in changed where isSessionTranscript(path) {
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey]),
                  let modified = values.contentModificationDate
            else {
                knownPaths[path] = nil   // vanished
                continue
            }
            knownPaths[path] = (modified, UInt64(values.fileSize ?? 0),
                                values.creationDate ?? modified)
        }

        var out: [(String, ParsedTail, Date, Date)] = []
        for (path, meta) in knownPaths {
            guard isFresh(path, meta.modified, now) else { continue }
            guard let tail = reader.read(path: path, modified: meta.modified, size: meta.size)
            else { continue }
            out.append((path, tail, meta.modified, meta.created))
        }
        return out
    }

    /// Only `<root>/<project>/<session>.jsonl` is a session. FSEvents reports the
    /// subagent files below it too.
    private func isSessionTranscript(_ path: String) -> Bool {
        guard path.hasSuffix(".jsonl") else { return false }
        // FSEvents reports resolved paths: `/private/var/…` for a root under `/var`.
        for base in [root, resolvedRoot] where path.hasPrefix(base + "/") {
            return path.dropFirst(base.count + 1).split(separator: "/").count == 2
        }
        return false
    }

    private func isFresh(_ path: String, _ modified: Date, _ now: Date) -> Bool {
        now.timeIntervalSince(modified) < Self.staleAfter || busyPaths.contains(path)
    }

    /// The enumerator prefetches the attributes asked for, batching the `stat`s. Doing
    /// it per path instead cost 517 syscalls, 30 ms a refresh, 1,5 % of a core.
    private func transcripts(now: Date) -> [(path: String, tail: ParsedTail, modified: Date, created: Date)] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey, .fileSizeKey, .creationDateKey, .isRegularFileKey,
            .isDirectoryKey,
        ]
        guard let walker = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var out: [(String, ParsedTail, Date, Date)] = []
        for case let url as URL in walker {
            // `<project>/<session>/` holds subagent and workflow transcripts: same
            // `sessionId`, same `cwd`, and fresher than the parent while they run.
            if walker.level >= 2, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                walker.skipDescendants()
                continue
            }
            guard walker.level == 2, url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            guard isFresh(url.path, modified, now) else { continue }

            let path = url.path
            let size = UInt64(values.fileSize ?? 0)
            guard let tail = reader.read(path: path, modified: modified, size: size)
            else { continue }
            let created = values.creationDate ?? modified
            knownPaths[path] = (modified, size, created)
            out.append((path, tail, modified, created))
        }
        return out
    }
}
