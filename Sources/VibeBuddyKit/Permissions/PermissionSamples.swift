import Foundation

/// One believable request per kind of summary, for `--simulate-permission`.
///
/// The alternative is judging a panel by running Claude Code and hoping it asks
/// for the right kind of thing. Six kinds, six chances of waiting a long while
/// for the one you wanted to look at — and `AskUserQuestion` in particular
/// arrives when the model decides to, not when you are ready to look.
///
/// In the Kit rather than in the app so the tests can use the same fixtures the
/// eye judges. A sample that has drifted from what the parser produces is a
/// rehearsal of the wrong play.
public enum PermissionSamples {

    public static let kinds = ["shell", "diff", "write", "read", "url",
                               "question", "plan", "other"]

    /// A **queue** of questions, oldest first, for `--simulate-questions`.
    ///
    /// One sample shows a panel; only several show the thing the queue was
    /// written for. Answering the head must reveal the next one, the « +N en
    /// attente » counter must count down, and the window must resize between
    /// two questions of different lengths — none of which a single request can
    /// demonstrate, and none of which had ever been looked at.
    ///
    /// Deliberately uneven: a one-line question, a long one, a plan. Three
    /// questions of the same size would prove the panel keeps its height, not
    /// that it follows.
    public static func questions(_ count: Int, at now: Date = Date()) -> [PermissionRequestModel] {
        let asks: [(String, [String])] = [
            ("Le curseur « Taille de la pastille » doit devenir quoi ?",
             ["Curseur = pastille seule", "Deux curseurs séparés",
              "Garder couplé, corriger le débordement"]),
            ("On garde le plancher à 200 pt ?", ["Oui", "Non"]),
            ("""
                La mesure hors écran construit un NSHostingView par demande.
                À l'usage c'est une fois par permission, jamais par image.
                Mais c'est un coût que le panneau ne payait pas avant, et le
                dépôt a déjà payé deux fois un pipeline de rendu qu'il n'avait
                pas demandé — ImageRenderer, puis Canvas.

                On le garde, on le mesure d'abord, ou on calcule la hauteur à
                la main comme PillLayout le fait ?
                """,
             ["Garder la mesure", "Mesurer d'abord son coût",
              "Calculer à la main, comme PillLayout"]),
            ("Quel genre ajouter ensuite aux échantillons ?",
             ["MultiEdit", "WebFetch avec un domaine long", "Aucun"]),
        ]

        return (0..<max(0, count)).map { index in
            // Its own id per entry: the queue finds an entry by id, and two
            // samples sharing one would answer each other's request.
            let ask = asks[index % asks.count]
            return PermissionRequestModel(
                id: "sim-q\(index)", toolName: "AskUserQuestion", sessionID: "simulation",
                cwd: FileManager.default.currentDirectoryPath,
                summary: .question(prompt: ask.0, options: ask.1),
                suggestions: [], receivedAt: now)
        }
    }

    /// - Parameter kind: one of `kinds`. Anything else gives the shell one.
    public static func model(_ kind: String, at now: Date = Date()) -> PermissionRequestModel {
        let common: (String, String, PermissionRequestModel.Summary, [String])
            -> PermissionRequestModel = { id, tool, summary, suggestions in
                PermissionRequestModel(
                    id: id, toolName: tool, sessionID: "simulation",
                    cwd: FileManager.default.currentDirectoryPath,
                    summary: summary, suggestions: suggestions, receivedAt: now)
            }

        switch kind {
        case "diff":
            return common("sim-diff", "Edit", .diff(
                path: "Sources/VibeBuddyKit/Buddy/PillLayout.swift",
                before: """
                    let slot = min(max(natural, emptySlotWidth), maxSlotWidth)
                    return PillLayout(
                        leftWidth: slot,
                        rightWidth: slot,
                    """,
                after: """
                    let slot = min(max(natural, floor), maxSlotWidth)
                    return PillLayout(
                        leftWidth: slot,
                        rightWidth: slot,
                        buddyBox: box,
                    """), ["Edit"])

        case "write":
            return common("sim-write", "Write", .write(
                path: "docs/perf/2026-08-21-A.csv",
                contents: "scenario,rss,footprint,wakeups\nA,38.2,11.1,0\n"), ["Write"])

        case "read":
            return common("sim-read", "Read", .read(path: "/etc/hosts"), ["Read"])

        case "url":
            return common("sim-url", "WebFetch",
                          .url("https://developer.apple.com/documentation/appkit/nsevent"),
                          ["WebFetch(domain:developer.apple.com)"])

        case "question":
            return common("sim-question", "AskUserQuestion", .question(
                prompt: "Le curseur « Taille de la pastille » doit devenir quoi ?",
                options: ["Curseur = pastille seule", "Deux curseurs séparés",
                          "Garder couplé, corriger le débordement"]), [])

        case "plan":
            // `ExitPlanMode` is a question with **no options**: its prompt is
            // the plan itself, and the panel's own Deny / Allow bar says the
            // two things there are to say about one. Its own sample because it
            // is the tallest thing the panel ever draws — long enough here to
            // pass the 260 pt ceiling and prove the block scrolls instead of
            // pushing the decision bar off the bottom.
            return common("sim-plan", "ExitPlanMode", .question(
                prompt: """
                    ## Ajuster la hauteur du panneau à son contenu

                    1. `PermissionPanelView` — remplacer `maxHeight: .infinity` \
                    sur le résumé par un `Spacer(minLength: 0)`, sans quoi \
                    toute demande redemande la hauteur maximale.
                    2. `AskQuestionView` — mesurer le bloc de prompt et prendre \
                    le plus petit de sa hauteur et de son plafond. Le plafond \
                    reste, le plancher tombe.
                    3. `NotchPanel` — `panelSize` devient une propriété, \
                    mesurée une fois par demande sur un `NSHostingView` hors \
                    écran, bornée entre 200 et 460 pt.
                    4. Le redimensionnement passe par `resizeToContent`, pas \
                    par `applyEffects` : celui-ci masque le contenu et le \
                    replanifie, ce qui ferait clignoter le panneau à chaque \
                    demande suivante.
                    5. `hover.pillRect` reçoit la destination, jamais le cadre \
                    courant — une sonde restée sur l'ancien rect referme un \
                    panneau où le curseur se trouve.
                    6. `setPermission` remesure **inconditionnellement** : une \
                    hauteur laissée par une demande partie dimensionnerait la \
                    vue des sessions à une question que plus personne ne \
                    regarde.
                    7. `AppCoordinator` retire ses fenêtres sur `SIGTERM`, \
                    sans quoi ce qui était à l'écran y reste jusqu'à ce que \
                    l'arrière-plan se repeigne.

                    Vérification : capture des quatre genres, `swift test`, et \
                    la zone comparée au pixel avant et après un `kill -TERM`.
                    """,
                options: []), [])

        case "other":
            return common("sim-other", "SomeFutureTool", .other(fields: [
                .init(name: "alpha", value: "premier"),
                .init(name: "count", value: "3"),
                .init(name: "zeta", value: "dernier"),
            ]), [])

        default:
            // A command with teeth: the panel has to read well when the answer
            // matters, not only when it is `ls`.
            return common("sim-shell", "Bash", .shell(
                command: "rm -rf .build dist && swift build -c release",
                description: "Repartir d'un build propre"), ["Bash(rm:*)", "Bash"])
        }
    }
}
