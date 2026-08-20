import AppKit
import VibeBuddyKit

/// `--info` — what the app resolved about this machine, and what it costs now.
@MainActor
enum Diagnostics {

    static func run() -> Never {
        _ = NSApplication.shared  // needed for NSScreen

        print("── écrans ──")
        for screen in NSScreen.screens {
            let id = NotchGeometry.displayID(of: screen).map(String.init) ?? "?"
            let notch = NotchGeometry.notchSize(of: screen)
            let frame = screen.frame
            print(String(
                format: "  id=%-10@ %.0f×%.0f  inset_top=%.0f  encoche=%@",
                id as NSString, frame.width, frame.height,
                screen.safeAreaInsets.top,
                notch.map { String(format: "%.0f×%.0f", $0.width, $0.height) } ?? "aucune"
            ))
        }

        print("\n── géométrie retenue ──")
        if let g = NotchGeometry.resolve() {
            print("  écran        \(g.screenID)")
            print("  cadre        \(Int(g.screenFrame.width))×\(Int(g.screenFrame.height))")
            print("  encoche      \(g.notchSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? "aucune")")
            print("  haut. pastille \(Int(g.pillHeight)) pt")
        } else {
            print("  aucun écran résolu")
        }

        print("\n── budget de réveil ──")
        let wake = WakeCoordinator()
        print("  aucun client        \(fmt(wake.effectiveInterval))")
        for cadence in Cadence.allCases where cadence != .off {
            wake.register(id: "probe", cadence: cadence) {}
            print(String(
                format: "  1 client %-8@ %@  → %.2f réveil/s",
                String(describing: cadence) as NSString,
                fmt(wake.effectiveInterval), wake.wakeupsPerSecond
            ))
        }
        wake.suspend()
        print("  suspendu (veille)   \(fmt(wake.effectiveInterval))  → 0 réveil/s")

        print("\n── budget d'animation ──")
        let budget = AnimationBudget()
        for (visible, busy) in [(false, true), (true, false), (true, true)] {
            budget.update(isVisible: visible, isBusy: busy)
            print(String(
                format: "  visible=%-5@ actif=%-5@ → %-8@ %.0f fps  animations implicites: %@",
                String(visible) as NSString, String(busy) as NSString,
                String(describing: budget.tier) as NSString,
                budget.frameRate,
                budget.allowsImplicitAnimations ? "oui" : "non"
            ))
        }

        print("\n── cadres calculés pour cette machine ──")
        if let g = NotchGeometry.resolve() {
            let pill = CGSize(width: NotchPanel.carrierWidth, height: 32)
            let panel = CGSize(width: NotchPanel.carrierWidth, height: 460)
            for (label, size) in [("pastille", pill), ("panneau ", panel)] {
                for (name, frac) in [("gauche", 0.0), ("centre", 0.5), ("droite", 1.0)] {
                    let r = NotchFrameSolver.frame(size: size, geometry: g, fraction: frac)
                    let flush = r.maxY == g.screenFrame.maxY ? "  ← à ras de l'encoche" : ""
                    print(String(format: "  %@ %-6@ x=%7.1f y=%7.1f  %.0f×%.0f%@",
                                 label, name as NSString, r.minX, r.minY, r.width, r.height,
                                 flush as NSString))
                }
            }
            print("\n── disposition de la pastille ──")
        if let g = NotchGeometry.resolve() {
            var loader = BuddyLoader()
            let buddy = loader.load(id: UserDefaults.standard.string(forKey: "vibebuddy.buddy") ?? BuiltInBuddy.id).manifest
            for (label, count, alert) in [("repos", 0, String?.none), ("2 sessions", 2, nil),
                                          ("10 sessions", 10, nil),
                                          ("alerte", 2, "notch terminé")] {
                let l = PillLayout.resolve(geometry: g, buddy: buddy,
                                           sessionCount: count, alertText: alert)
                print(String(format: "  %-12@ gauche %5.1f · encoche %5.1f · droite %5.1f = %6.1f pt · décalage %+.1f",
                             label as NSString, l.leftWidth, l.notchWidth, l.rightWidth,
                             l.totalWidth, l.notchAlignmentOffset))
            }
        }

        print("\n── aimants ──")
            for f in [0.02, 0.28, 0.48, 0.97] {
                let snapped = NotchFrameSolver.snap(fraction: CGFloat(f), size: pill, geometry: g)
                let caught = abs(snapped - CGFloat(f)) > 0.0001
                print(String(format: "  %.2f → %.2f  %@", f, snapped,
                             (caught ? "capté" : "laissé libre") as NSString))
            }
        }

        print("\n── transcripts (parseur contre données réelles) ──")
        let root = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        var files: [(String, Date)] = []
        if let walker = fm.enumerator(atPath: root) {
            for case let rel as String in walker where rel.hasSuffix(".jsonl") {
                let full = "\(root)/\(rel)"
                if let a = try? fm.attributesOfItem(atPath: full),
                   let m = a[.modificationDate] as? Date { files.append((full, m)) }
            }
        }
        files.sort { $0.1 > $1.1 }
        var unrecognised: [String: Int] = [:]
        let started = Date()
        for (path, _) in files.prefix(10) {
            guard let data = JSONLTailReader.tail(of: path, bytes: 64 * 1024) else { continue }
            let t = TranscriptParser.parse(data)
            for (k, v) in t.unrecognised { unrecognised[k, default: 0] += v }
            let what = t.turnEnded
                ? "tour terminé"
                : (t.status.map { label in
                      Strings.french.label(for: label)
                          + (t.subject.map { " · \($0)" } ?? "")
                  } ?? "—")
            print(String(format: "  %-16@ ctx=%7d %@%@ %@",
                ((t.cwd ?? "—") as NSString).lastPathComponent as NSString,
                t.contextTokens,
                (t.permissionMode.map { "mode=\($0) " } ?? "") as NSString,
                (t.lastResultWasError ? "ERREUR " : "") as NSString,
                String(what.prefix(60)) as NSString))
        }
        let ms = Date().timeIntervalSince(started) * 1000
        print(String(format: "  %d transcripts au total · %.1f ms pour 10 queues", files.count, ms))
        // Parade R9 : ce que le parseur n'a pas su lire est compté, pas ignoré.
        print("  types non reconnus : \(unrecognised.isEmpty ? "aucun" : String(describing: unrecognised))")

        print("\n── sessions vivantes (processus + transcript) ──")
        let store = SessionStore()
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var live: [AgentSession] = []
        let t0 = Date()
        // Detached: a plain `Task` starts on the current actor, and the main
        // thread is about to block on the semaphore — it would never run.
        Task.detached { live = await store.refresh(); sem.signal() }
        _ = sem.wait(timeout: .now() + 5)
        let refreshMs = Date().timeIntervalSince(t0) * 1000

        if live.isEmpty {
            print("  aucune session")
        }
        for session in live.prefix(8) {
            let term = session.pid.map { TerminalFocusProbe.hostingTerminal(of: $0) } ?? nil
            // The tty is what the jump matches on.
            let tty = session.pid.flatMap { ProcessLookup.tty(of: $0) }
            print(String(format: "  %@ %-14@ pid=%-7@ ctx=%3.0f%%  term=%-10@ %-12@ %@",
                (session.isLive ? "●" : "○") as NSString,
                (session.projectName as NSString),
                (session.pid.map(String.init) ?? "—") as NSString,
                session.contextFraction * 100,
                (term.flatMap { ProcessLookup.name(of: $0) } ?? "tmux/?") as NSString,
                ((tty?.replacingOccurrences(of: "/dev/", with: "") ?? "—")
                    + (session.pid.map { TerminalJumper.canSelectTab(agentPID: $0) } == true
                       ? " ✔" : "")) as NSString,
                (session.awaitingAnswer
                    ? "⏳ " + (session.question ?? "question")
                    : (session.status.map { Strings.french.label(for: $0) } ?? "—")) as NSString))
        }
        print(String(format: "  %d sessions · refresh en %.1f ms", live.count, refreshMs))
        print("  un terminal est au premier plan : \(TerminalFocusProbe.isAnyTerminalFrontmost())")
        if let front = NSWorkspace.shared.frontmostApplication {
            print("  premier plan : \(front.localizedName ?? "?") · \(front.bundleIdentifier ?? "?")")
        }
        // La chaîne parent telle que libproc la voit — c'est elle qui décide si
        // le terminal hôte est identifiable, et son échec est muet sans ça.
        if let pid = live.first(where: { $0.pid != nil })?.pid {
            print("  chaîne parent depuis \(pid) :")
            var cur = pid
            for hop in 1...TerminalFocusProbe.maxHops {
                guard let parent = ProcessLookup.parent(of: cur), parent > 1 else { break }
                let name = ProcessLookup.name(of: parent) ?? "?"
                let isTerm = TerminalFocusProbe.terminalNames.contains(name)
                print(String(format: "    %d. pid=%-7d %-20@ %@", hop, parent,
                             name as NSString, (isTerm ? "← terminal" : "") as NSString))
                cur = parent
            }
        }

        print("\n── buddies ──")
        switch SupportDirectory.migrate() {
        case .notNeeded: break
        case let .moved(from): print("  dossier déplacé depuis \(from)")
        case let .bothPresent(legacy): print("  ⚠ ancien dossier encore présent : \(legacy)")
        case let .failed(reason): print("  ⚠ migration impossible : \(reason)")
        }
        // `3.0 img/s` reads as a measurement; `3` reads as what was written.
        func rate(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
        let installed = BuddyLoader.available()
        let active = UserDefaults.standard.string(forKey: "vibebuddy.buddy") ?? BuiltInBuddy.id
        for manifest in installed {
            let mark = manifest.id == active ? "●" : "○"
            let plate = manifest.face
            print("  \(mark) \(manifest.id)  \(manifest.expressions.count) expressions · "
                  + "écran \(rate(Double(plate.width)))×\(rate(Double(plate.height))) "
                  + (plate.silhouette == .oval
                     ? "ovale"
                     : "r\(rate(Double(plate.radius)))"))
            for name in BuddyExpression.allCases {
                guard let e = manifest.expression(name) else { continue }
                // Printed per expression, overridden or not: an override that
                // failed to parse looks like an inherited value otherwise.
                print(String(format: "      %-9@ %@  %-8@ %@",
                             name.rawValue as NSString,
                             (e.colour ?? manifest.colour) as NSString,
                             e.motion.rawValue as NSString,
                             BuddyExportWriter.poseLine(e.eye) as NSString))
                // The cells themselves, because a face is authored by eye and
                // this is the only faithful preview outside the running app.
                if manifest.id == active {
                    for row in faceRows(spec: e.eye, plate: plate) { print("        \(row)") }
                }
            }
        }
        // Follows `VIBEBUDDY_FACE` so any expression's sequence can be read
        // without launching the app and waiting for the right state.
        var idleLoader = BuddyLoader()
        let traced = AppCoordinator.forcedFace ?? .idle
        if let spec = idleLoader.load(id: active).manifest.expressions[traced.rawValue]?.eye {
            print("  séquence \(traced.rawValue) — un temps de \(spec.beat) s")
            for index in 0..<18 {
                let beat = EyeAnimation.beat(at: index, spec: spec)
                let frame = EyeAnimation.at(
                    phase: Double(index) * spec.beat + spec.beat * 0.7, spec: spec)
                print(String(
                    format: "    %2d  %-7@ regard %+5.1f,%+5.1f pt   profondeur %.2f   ouverture %.2f   roulis %+.1f   dissymétrie %+.2f",
                    index, beat.rawValue as NSString,
                    Double(frame.gaze.width), Double(frame.gaze.height),
                    Double(frame.depth), Double(frame.squeeze), Double(frame.roll), Double(frame.lopsided)))
            }
        }
        print("  dossier : \(BuddyLoader.searchPath)")

        print("\n── langue ──")
        let l10n = Localisation()
        print("  réglage        \(l10n.language.rawValue) (\(l10n.language.displayName))")
        print("  résolue        \(l10n.effective.rawValue)")
        print("  macOS préfère  \(Locale.preferredLanguages.prefix(3).joined(separator: ", "))")
        print("  locale dates   \(l10n.locale.identifier)")
        for lang in AppLanguage.allCases where lang != .system {
            let s = Strings.for(lang)
            print("  \(lang.rawValue) → \(s.usageTitle) · \(s.emptyHint)")
        }

        print("\n── consommation Claude ──")
        let usageSem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: UsageOutcome = .failed("timeout")
        Task.detached { outcome = await UsageClient().fetch(); usageSem.signal() }
        _ = usageSem.wait(timeout: .now() + 10)
        switch outcome {
        case let .success(u):
            for (label, w) in [("session (5 h)", u.fiveHour), ("semaine (7 j)", u.sevenDay)] {
                if let w {
                    print(String(format: "  %-14@ %5.1f %%  reset %@", label as NSString,
                                 w.utilisation,
                                 (w.resetsAt.map { UsageBar.resetText($0) } ?? "—") as NSString))
                } else {
                    print("  \(label)  indisponible")
                }
            }
        case .noCredentials: print("  pas de jeton lisible")
        case let .rateLimited(after):
            // The header is a floor, not a schedule: measured on 2026-08-20 the
            // endpoint refuses with `retry-after: 0`, so what the app will
            // actually wait is its own backoff.
            print(String(format: "  limité (retry-after %.0f s) → attente réelle %.0f s min",
                         after, UsageState.backoffFloor))
            if let cached = UsageCache().load() {
                let age = Int(Date().timeIntervalSince(cached.fetchedAt) / 60)
                print(String(format: "  dernière lecture en cache : %.0f %% / %.0f %% il y a %d min",
                             cached.fiveHour?.utilisation ?? -1,
                             cached.sevenDay?.utilisation ?? -1, age))
            } else {
                print("  aucune lecture en cache")
            }
        case let .failed(reason): print("  échec : \(reason)")
        }

        let s = PerfProbe.sample()
        print("\n── coût actuel de ce process ──")
        print(String(format: "  phys_footprint  %.1f Mo   (budget < 40)", s.footprintMB))
        print(String(format: "  RSS             %.1f Mo   (indicatif)", s.residentMB))
        print(String(format: "  réveils inactifs %llu", s.idleWakeups))
        print("")
        exit(0)
    }

    private static func fmt(_ interval: TimeInterval?) -> String {
        interval.map { String(format: "tick %.0fs ", $0) } ?? "aucun timer"
    }

    /// One eyes expression, drawn as the cells it actually lights up.
    ///
    /// A `.buddy` face is authored by eye and there is no other faithful
    /// preview outside the running app: every attempt to judge a pose from its
    /// numbers alone got it wrong. Sampled on a beat that looks straight ahead,
    /// so the preview is the pose rather than a glance.
    static func faceRows(spec: EyeSpec, plate: BuddyManifest.FacePlate) -> [String] {
        let pitch = BuddyView.defaultPixelSize
        let size = CGSize(width: plate.width, height: plate.height)
        var phase = 0.0
        for index in 0..<64 where EyeAnimation.beat(at: index, spec: spec) == .ahead {
            phase = Double(index) * spec.beat + spec.beat * 0.6
            break
        }
        let animation = EyeAnimation.at(phase: phase, spec: spec)
        // Grain and tear included: a `failed` face whose screen is not tearing
        // is not the face the app shows.
        let rendered = EyeRaster.frame(
            in: size, pose: spec.pose, animation: animation, pitch: pitch,
            grain: spec.grain, glitch: spec.glitch,
            tick: Int(phase * EyeSpec.noiseRate))
        let columns = max(1, Int(size.width / pitch))
        let rows = max(1, Int(size.height / pitch))
        var grid = [[Character]](
            repeating: [Character](repeating: " ", count: columns), count: rows)
        for (cells, mark) in [(rendered.grain, Character("·")), (rendered.dim, Character("░")), (rendered.lit, Character("█"))] {
            for cell in cells {
                let row = Int(cell.minY / pitch), column = Int(cell.minX / pitch)
                guard grid.indices.contains(row), grid[row].indices.contains(column) else { continue }
                grid[row][column] = mark
            }
        }
        return grid.map { String($0) }
    }
}
