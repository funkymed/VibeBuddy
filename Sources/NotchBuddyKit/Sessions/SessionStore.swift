import Foundation

/// The single source of truth for what agents are doing.
///
/// # Why one owner
///
/// The reference implementation keeps three, and they disagree: sessions derived
/// from transcripts plus `libproc`, PIDs derived from a hook's socket peer, and
/// permission modes indexed by working directory rather than by session. The
/// result is matching on `cwd` for want of anything better, and an `lsof` call
/// that contradicts a comment elsewhere in the same repository.
///
/// Here there is one owner and three *inputs*, each authoritative over exactly
/// one thing:
///
/// - **the process** is the truth about liveness,
/// - **the transcript** is the truth about content, mode and progress,
/// - **the hook**, when RFC-006 lands, is the truth about identity — a PID tied
///   to a session id rather than inferred from a shared directory.
///
/// Primary key is the session id. `cwd` is a secondary index and nothing more.
///
/// # "Event-driven" is a description, not a design
///
/// Transcript changes arrive from FSEvents. Process death emits **no filesystem
/// event whatsoever**, so liveness stays a poll — lazily, 30 s at rest and 2 s
/// while something is happening, rather than the reference's flat 1 Hz with a
/// `fork` in it.
public actor SessionStore {

    /// Contracted freshness, so nobody quietly reinstates a 1 Hz timer the first
    /// time a status looks stale.
    public static let activeLatency: TimeInterval = 2
    public static let restingLatency: TimeInterval = 30

    /// How long an incremental refresh may go before a full walk is forced.
    /// Bounds how stale the deleted-transcript case can get.
    public static let fullWalkInterval: TimeInterval = 120

    /// A transcript untouched for longer than this is not shown at all. Claude
    /// Code never deletes them, so without this the list is months of history.
    public static let staleAfter: TimeInterval = 15 * 60

    /// Above this many prompt tokens a session is taken to be running with the
    /// 1M context window rather than the default 200k.
    public static let largeContextThreshold = 200_000
    public static let defaultContextWindow = 200_000
    public static let largeContextWindow = 1_000_000

    private let root: String
    private var reader = JSONLTailReader()

    /// Where liveness comes from: normalised cwd → running agent pids.
    ///
    /// Injectable because the alternative is untestable. Liveness comes from
    /// real processes, and no test can conjure an agent running in a temporary
    /// directory — so without this seam the alert path could only ever be
    /// exercised by hand, from inside a session that is by definition busy
    /// running the test.
    private let liveness: @Sendable () -> [String: [pid_t]]

    /// Last non-zero context size per session.
    ///
    /// Sticky on purpose: a tail that happens to land on a user turn or a tool
    /// result carries no `usage` block, and without this the context gauge drops
    /// to zero and back on alternate reads. The reference implementation learned
    /// the same lesson.
    private var stickyTokens: [String: Int] = [:]
    /// Once a session is seen above the threshold it is pinned to the large
    /// window. Sessions do not shrink back, and flip-flopping the denominator
    /// would make the gauge jump.
    private var stickyWindow: [String: Int] = [:]

    private var current: [AgentSession] = []
    private var subscribers: [UUID: AsyncStream<[AgentSession]>.Continuation] = [:]

    public init(
        root: String? = nil,
        liveness: (@Sendable () -> [String: [pid_t]])? = nil
    ) {
        self.root = root
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        self.liveness = liveness ?? { ProcessLookup.agentPIDs() }
    }

    // MARK: - Reading

    public var sessions: [AgentSession] { current }

    /// Live sessions only — a transcript alone never proves one.
    public var liveSessions: [AgentSession] { current.filter(\.isLive) }

    public func updates() -> AsyncStream<[AgentSession]> {
        let id = UUID()
        return AsyncStream { continuation in
            subscribers[id] = continuation
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }

    // MARK: - Refresh

    /// Paths seen on the last full walk, so an incremental refresh knows the
    /// corpus without re-enumerating it.
    private var knownPaths: [String: (modified: Date, size: UInt64, created: Date)] = [:]
    private var lastFullWalk: Date = .distantPast

    /// Rebuild from the three inputs.
    ///
    /// `changed` is the path list from FSEvents. When present, only those files
    /// are re-stat'ed and the rest of the corpus is taken from the last full
    /// walk — ~1 ms instead of ~17 ms on a 517-file corpus.
    ///
    /// A full walk still runs periodically, because the incremental path cannot
    /// see a transcript that was *deleted*, and because FSEvents paths are a
    /// hint rather than a guarantee.
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

        // Group by working directory so the capacity rule below can be applied.
        var byCwd: [String: [(path: String, tail: ParsedTail, modified: Date, created: Date)]] = [:]
        for candidate in candidates {
            seenPaths.insert(candidate.path)
            guard let cwd = candidate.tail.cwd else { continue }
            byCwd[ProcessLookup.normalise(cwd), default: []].append(candidate)
        }

        for (cwd, group) in byCwd {
            let pids = live[cwd] ?? []
            // Freshest first, then keep at most as many as there are processes
            // actually running here. mtime lies about liveness; the process
            // count does not.
            let ranked = group.sorted { $0.modified > $1.modified }
            for (index, candidate) in ranked.enumerated() {
                let isLive = index < pids.count
                guard isLive || now.timeIntervalSince(candidate.modified) < Self.staleAfter else { continue }
                sessions.append(makeSession(
                    candidate: candidate,
                    cwd: cwd,
                    // Positional pairing is a stopgap. It is arbitrary when two
                    // agents share a directory, which is exactly what the hook's
                    // session-to-PID mapping will fix in RFC-006.
                    pid: index < pids.count ? pids[index] : nil,
                    isLive: isLive
                ))
            }
        }

        sessions.sort { $0.lastActivity > $1.lastActivity }
        reader.evict(keeping: seenPaths)

        if sessions != current {
            current = sessions
            for continuation in subscribers.values { continuation.yield(sessions) }
        }
        return sessions
    }

    // MARK: - Assembly

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
        let window = stickyWindow[sessionID] ?? Self.defaultContextWindow

        return AgentSession(
            id: sessionID,
            cwd: cwd,
            projectName: (cwd as NSString).lastPathComponent,
            model: tail.model ?? "",
            effort: tail.effort ?? "",
            startedAt: candidate.created,
            lastActivity: tail.lastTimestamp ?? candidate.modified,
            status: tail.turnEnded ? "" : tail.status,
            action: tail.action,
            permissionMode: tail.permissionMode ?? "",
            contextTokens: tokens,
            contextWindow: window,
            pid: pid,
            isLive: isLive,
            subject: tail.subject,
            turnEnded: tail.turnEnded,
            lastResultWasError: tail.lastResultWasError,
            subagentsRunning: tail.subagentsRunning
        )
    }

    /// Re-stat only the paths FSEvents named, and reuse the rest.
    private func incremental(changed: [String], now: Date)
        -> [(path: String, tail: ParsedTail, modified: Date, created: Date)] {
        for path in changed where path.hasSuffix(".jsonl") {
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
            guard now.timeIntervalSince(meta.modified) < Self.staleAfter else { continue }
            guard let tail = reader.read(path: path, modified: meta.modified, size: meta.size)
            else { continue }
            out.append((path, tail, meta.modified, meta.created))
        }
        return out
    }

    /// Walk the corpus and parse only what is recent enough to matter.
    ///
    /// The enumerator prefetches the attributes it is asked for, which turns one
    /// `stat` per file into a batched read. The first version called
    /// `attributesOfItem` per path instead — 517 separate syscalls on this
    /// machine, measured at 30 ms a refresh. At the active cadence that is 1.5 %
    /// of a core, and during an FSEvents burst it reaches the 3 % activity
    /// budget on its own.
    ///
    /// The staleness check comes before the parse, so a cold corpus costs the
    /// walk and nothing else.
    private func transcripts(now: Date) -> [(path: String, tail: ParsedTail, modified: Date, created: Date)] {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey, .fileSizeKey, .creationDateKey, .isRegularFileKey,
        ]
        guard let walker = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var out: [(String, ParsedTail, Date, Date)] = []
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            guard now.timeIntervalSince(modified) < Self.staleAfter else { continue }

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

    public var cachedTranscripts: Int { reader.cachedCount }
}
