import Testing
import Foundation
@testable import VibeBuddyKit

/// End-to-end, against a real temporary directory.
///
/// These exist because of a crash no unit test could have caught: the callback
/// read `eventPaths` as a `CFArray` when the stream had not been created with
/// `kFSEventStreamCreateFlagUseCFTypes`, so it was really a C `char **`. That is
/// not a type error the compiler can see — it is a wild pointer sent an
/// Objective-C message, and it only fails once a real event arrives.
///
/// So the assertion that matters here is not "the paths are right". It is
/// "the callback runs at all against a live stream".
@Suite("ProjectsWatcher", .serialized)
struct ProjectsWatcherTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibebuddy-fsevents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a write in the watched tree reaches the callback", .timeLimit(.minutes(1)))
    func firesOnWrite() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let box = PathBox()
        let watcher = ProjectsWatcher { paths in box.record(paths) }
        watcher.start(path: dir.path)
        defer { watcher.stop() }

        // FSEvents needs a moment to arm before it will report anything.
        try await Task.sleep(for: .milliseconds(600))

        let file = dir.appendingPathComponent("session.jsonl")
        for i in 0..<4 {
            try Data("{\"n\":\(i)}\n".utf8).write(to: file)
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: .seconds(2))

        #expect(box.callCount > 0, "the callback never ran — the stream is not delivering")
        // The paths are a hint, not a contract, so this only checks they are
        // readable strings rather than garbage.
        for path in box.paths {
            #expect(!path.isEmpty)
            #expect(path.hasPrefix("/"))
        }
    }

    @Test("stopping is idempotent and safe before any start")
    func stopIsSafe() {
        let watcher = ProjectsWatcher { _ in }
        watcher.stop()
        watcher.stop()
        #expect(!watcher.isRunning)
    }

    @Test("starting twice does not leave a stream behind")
    func restartIsClean() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let watcher = ProjectsWatcher { _ in }
        watcher.start(path: dir.path)
        watcher.start(path: dir.path)
        #expect(watcher.isRunning)
        watcher.stop()
        #expect(!watcher.isRunning)
    }
}

/// Collects callback results across threads — FSEvents delivers on its own queue.
private final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    private var calls = 0

    func record(_ paths: [String]) {
        lock.lock(); defer { lock.unlock() }
        storage.append(contentsOf: paths)
        calls += 1
    }
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
}
