import Foundation
import CoreServices

/// Replaces a 1 Hz poll: the `pgrep` alone cost 11,34 ms per tick, 1,13 % of a core.
/// `kFSEventStreamCreateFlagFileEvents` carries real paths, so a consumer re-reads three
/// files (~1 ms) instead of walking five hundred (~17 ms).
public final class ProjectsWatcher: @unchecked Sendable {
    public static let latency: CFTimeInterval = 1.0

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "fr.funkylab.vibebuddy.fsevents")
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

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ProjectsWatcher>.fromOpaque(info).takeUnretainedValue()

            // `eventPaths` is a C `char ` unless kFSEventStreamCreateFlagUseCFTypes
            // is set, where it is a CFArray of CFStrings.
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
            // `NoDefer` fires at the *start* of the window: without it every update
            // pays a second.
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
