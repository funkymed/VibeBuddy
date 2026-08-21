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

    public static let kinds = ["shell", "diff", "write", "read", "url", "question", "other"]

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
