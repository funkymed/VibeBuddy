import AppKit
import VibeBuddyKit

// Entry point. `--bench <mode> <seconds>`, `--hover` and `--info` are optional.

let args = CommandLine.arguments

if let benchIndex = args.firstIndex(of: "--bench") {
    let mode = args.count > benchIndex + 1
        ? BenchHarness.Mode(rawValue: args[benchIndex + 1]) ?? .panel
        : .panel
    let seconds = args.count > benchIndex + 2
        ? Double(args[benchIndex + 2]) ?? 60
        : 60
    let label = args.count > benchIndex + 3 ? args[benchIndex + 3] : mode.rawValue
    MainActor.assumeIsolated {
        BenchHarness.run(mode: mode, seconds: seconds, label: label)
    }
}

if args.contains("--hover") {
    MainActor.assumeIsolated { HoverDiagnostics.run() }
}

if args.contains("--info") {
    MainActor.assumeIsolated { Diagnostics.run() }
}

let app = NSApplication.shared
let coordinator = AppCoordinator()
app.delegate = coordinator

app.run()
