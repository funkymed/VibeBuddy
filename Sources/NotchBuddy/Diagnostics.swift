import AppKit
import NotchBuddyKit

/// `--info` — what the app resolved about this machine, and what it currently
/// costs. Exists so the geometry and wake budget can be checked against reality
/// rather than trusted, and so a slowness report comes with numbers attached.
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
            let buddy = loader.load(id: UserDefaults.standard.string(forKey: "notchbuddy.buddy") ?? "emoji").manifest
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
                : (t.status.isEmpty ? "—" : t.status + (t.subject.map { " · \($0)" } ?? ""))
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
        // Detached: a plain Task starts on the current actor, and the main
        // thread is about to block on the semaphore — it would never run.
        Task.detached { live = await store.refresh(); sem.signal() }
        _ = sem.wait(timeout: .now() + 5)
        let refreshMs = Date().timeIntervalSince(t0) * 1000

        if live.isEmpty {
            print("  aucune session")
        }
        for session in live.prefix(8) {
            let term = session.pid.map { TerminalFocusProbe.hostingTerminal(of: $0) } ?? nil
            print(String(format: "  %@ %-14@ pid=%-7@ ctx=%3.0f%%  term=%-10@ %@",
                (session.isLive ? "●" : "○") as NSString,
                (session.projectName as NSString),
                (session.pid.map(String.init) ?? "—") as NSString,
                session.contextFraction * 100,
                (term.flatMap { ProcessLookup.name(of: $0) } ?? "tmux/?") as NSString,
                (session.status.isEmpty ? "—" : session.status) as NSString))
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
        // `3.0 img/s` reads as a measurement; `3` reads as what was written.
        func rate(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
        let installed = BuddyLoader.available()
        let active = UserDefaults.standard.string(forKey: "notchbuddy.buddy") ?? "emoji"
        for manifest in installed {
            let mark = manifest.id == active ? "●" : "○"
            let frames = manifest.expressions.values.map(\.frames.count).reduce(0, +)
            print("  \(mark) \(manifest.id)  \(manifest.expressions.count) expressions · "
                  + "\(frames) images · \(rate(manifest.framesPerSecond)) img/s")
            for name in BuddyExpression.allCases {
                guard let e = manifest.expression(name) else { continue }
                // The rate is printed per expression, overridden or not: the
                // question this section answers is "what is it actually doing",
                // and an override that silently failed to parse looks exactly
                // like an inherited value unless both are shown.
                print(String(format: "      %-9@ %@  %-5@ %@",
                             name.rawValue as NSString,
                             (e.colour ?? manifest.colour) as NSString,
                             (rate(manifest.rate(for: e)) + " img/s") as NSString,
                             (e.frames.first ?? "") as NSString))
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
                                 (w.resetsAt.map { UsageBarPreview.reset($0) } ?? "—") as NSString))
                } else {
                    print("  \(label)  indisponible")
                }
            }
        case .noCredentials: print("  pas de jeton lisible")
        case let .rateLimited(after): print(String(format: "  limité, réessai dans %.0f s", after))
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
}
