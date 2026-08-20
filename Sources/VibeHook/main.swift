import Foundation
import VibeHookProtocol

// Stub. The real bridge lands in RFC-006.
//
// Contract that already holds: never block Claude Code. Any unexpected input,
// any missing app, any error at all — exit 0 and let Claude fall back to its
// own prompt.

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard
    (try? JSONSerialization.jsonObject(with: stdinData)) as? [String: Any] != nil
else {
    exit(0)
}
exit(0)
