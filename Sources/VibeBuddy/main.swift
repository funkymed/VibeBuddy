import AppKit
import VibeBuddyKit

// Entry point.
//
// `--bench <mode> <seconds>` measures; `--info` reports. Neither is needed to
// run the app: launched from a terminal it runs until Ctrl-C, and from the
// panel until the power button.
//
// There used to be a `--demo <seconds>` flag that quit on a timer. It existed
// because *I* was launching the app detached from tooling and losing track of
// it — not a problem anyone running it from a shell has. Scaffolding for a
// difficulty of my own making, removed.

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
