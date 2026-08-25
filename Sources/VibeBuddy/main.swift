import AppKit
import VibeBuddyKit

// Entry point.

let args = CommandLine.arguments

// Registering the hook writes to a file that is the user's, so it is an explicit
// command that shows its diff and asks — never something a launch does on its own.
if args.contains("--install-hook") || args.contains("--uninstall-hook") {
    exit(HookInstallCommand.run(arguments: args))
}

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

// `--simulate-permission <genre>`, `--simulate-questions [n]` and `--simulate-finished`
// are read by `AppCoordinator`; listed here so the flags are findable from the entry
// point like every other one.
if args.contains("--help"), args.contains("--simulate-permission")
    || args.contains("--simulate-questions") || args.contains("--simulate-finished") {
    print("--simulate-permission <genre>  genres : \(PermissionSamples.kinds.joined(separator: " · "))")
    print("--simulate-questions [n]       n questions en file, 3 par défaut")
    print("--simulate-finished            l'alerte de fin de tâche, 30 s")
    exit(0)
}

if args.contains("--info") {
    MainActor.assumeIsolated { Diagnostics.run() }
}

let app = NSApplication.shared
let coordinator = AppCoordinator()
app.delegate = coordinator

app.run()
