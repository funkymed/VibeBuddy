import Foundation
import CoreServices

/// Watches `~/.claude/projects` and reports that something changed.
///
/// # Why this replaces a timer
///
/// The reference implementation polls once a second, forever: it walks the whole
/// project tree and shells out to `pgrep` on every tick, whether or not anything
/// happened. Measured on this machine, the `pgrep` alone is 11.34 ms per tick —
/// 1.13 % of a core, permanently, to learn nothing most of the time.
///
/// FSEvents inverts that. The kernel already knows when those files change; the
/// process sleeps until they do and costs nothing in between.
///
/// # It reports which files changed
///
/// `kFSEventStreamCreateFlagFileEvents` makes the callback carry actual paths
/// rather than just directories, and passing them on is what lets a consumer
/// re-read three files instead of walking five hundred. Measured here: a full
/// walk of the corpus costs ~17 ms, an incremental update costs ~1 ms.
///
/// The paths are still only a hint. Events coalesce, a path can appear twice in
/// one batch, and a file may already have changed again by the time it is read.
/// Consumers must treat the list as "at least these moved", never as "only
/// these".
///
/// # What it cannot do
///
/// It cannot replace process polling. **The death of a process emits no
/// filesystem event** — that part stays periodic, just lazily so. "Event-driven"
/// is a description of this class, not of the RFC.
public final class ProjectsWatcher: @unchecked Sendable {

    /// Coalescing window handed to FSEvents. A tool writing steadily produces a
    /// burst of events; one second turns that burst into one wake-up without
    /// making the UI feel behind.
    public static let latency: CFTimeInterval = 1.0

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "fr.funkylab.notchbuddy.fsevents")
    private let onChange: @Sendable ([String]) -> Void

    public init(onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    public func start(path: String) {
        stop()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        // The callback is a C function pointer and cannot capture, so `self`
        // travels through the context's `info` pointer.
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ProjectsWatcher>.fromOpaque(info).takeUnretainedValue()

            // `eventPaths` is a C `char **` unless kFSEventStreamCreateFlagUseCFTypes
            // is set, in which case it is a CFArray of CFStrings. Reading it the
            // wrong way is not a type error — it is a wild pointer sent an
            // Objective-C message, which crashes in objc_msgSend. This callback
            // reads it as the C array it actually is.
            let cStrings = paths.bindMemory(to: UnsafePointer<CChar>?.self, capacity: count)
            var list: [String] = []
            list.reserveCapacity(count)
            for i in 0..<count {
                guard let c = cStrings[i] else { continue }
                list.append(String(cString: c))
            }
            watcher.onChange(Array(Set(list)))
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            // `NoDefer` fires at the *start* of the coalescing window rather than
            // the end, so the first change of a burst is seen immediately and the
            // rest are absorbed. Without it every update pays the full second.
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    public var isRunning: Bool { stream != nil }
}
