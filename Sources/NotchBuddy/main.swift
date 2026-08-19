import AppKit
import NotchBuddyKit

// Entry point.
//
// `--bench` exists so the performance budget can be measured before there is
// anything to measure — see RFC-001 T1 and question D5.

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

if args.contains("--info") {
    MainActor.assumeIsolated { Diagnostics.run() }
}

// `--demo <seconds>` shows the pill and exits, so RFC-002 can be tried without
// leaving a windowless process running.
let demoSeconds: Double? = args.firstIndex(of: "--demo").map { i in
    args.count > i + 1 ? (Double(args[i + 1]) ?? 60) : 60
}

let app = NSApplication.shared
let coordinator = AppCoordinator()
app.delegate = coordinator

if let seconds = demoSeconds {
    let quit = DispatchSource.makeTimerSource(queue: .main)
    quit.schedule(deadline: .now() + seconds)
    quit.setEventHandler { exit(0) }
    quit.resume()
    let steps = """
    demo RFC-002 — \(Int(seconds))s

      1. une pastille cerclee d orange borde l encoche, en haut au centre
      2. survole-la : un panneau 560x460 se deploie
      3. eloigne le curseur : il se replie
      4. clique l horloge a travers une zone transparente du panneau
      5. glisse la pastille : elle s aimante a gauche / centre / droite

    """
    FileHandle.standardError.write(Data(steps.utf8))
}

app.run()
