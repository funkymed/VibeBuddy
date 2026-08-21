import Darwin
import Foundation
import VibeHookProtocol

// The hook Claude Code spawns on every registered event.
//
// **Its first duty is to never block Claude Code.** Any unexpected input, any
// missing app, any error at all: exit 0 and say nothing, and Claude falls back
// to its own prompt. A hook that hangs is worse than no hook — the user sees a
// frozen agent and blames the agent.
//
// Foundation and Darwin only. No AppKit, no SwiftUI: dyld loads what this binary
// links *before* `main` runs, on every tool call of every session. See RFC-006,
// decision D4, and the `HookIsForbiddenAppKit` test.

/// Exits 0 without writing anything. Claude Code treats an empty stdout as
/// "the hook has no opinion".
func giveUp() -> Never {
    exit(0)
}

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard let request = HookRequest.parse(stdinData) else { giveUp() }

guard let fd = try? HookSocket.connect(
    to: HookWire.socketPath,
    timeout: request.event.isBlocking ? HookWire.blockingTimeout : 2)
else { giveUp() }
defer { close(fd) }

guard let line = try? HookLine.encodeRequest(request),
      HookSocket.write(line, to: fd)
else { giveUp() }

// Fire-and-forget: everything except a permission request. The app wanted to
// know, it now knows, and Claude Code is not waiting on us.
guard request.event.isBlocking else { giveUp() }

guard let reply = HookSocket.readLine(from: fd),
      let decision = HookLine.decodeDecision(reply),
      let response = try? HookWire.encode(decision)
else { giveUp() }

FileHandle.standardOutput.write(response)
exit(0)
