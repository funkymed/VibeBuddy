import Darwin
import Foundation
import VibeHookProtocol

// The hook Claude Code spawns on every registered event.

/// Exits 0 without writing anything.
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

// Fire-and-forget: everything except a permission request.
guard request.event.isBlocking else { giveUp() }

guard let reply = HookSocket.readLine(from: fd),
      let decision = HookLine.decodeDecision(reply),
      let response = try? HookWire.encode(decision)
else { giveUp() }

FileHandle.standardOutput.write(response)
exit(0)
