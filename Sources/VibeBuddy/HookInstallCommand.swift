import Foundation
import VibeBuddyKit

/// `--install-hook` and `--uninstall-hook`.
///
/// Both show the diff and wait for a yes before touching anything. That file is
/// the user's, eleven kilobytes of hand-edited settings, and an app that
/// rewrites it on launch without asking is the failure R1 describes — the
/// backup makes a wrong write repairable, consent is what keeps it from
/// happening. `--yes` skips the prompt, for a script that already knows.
enum HookInstallCommand {

    static func run(arguments: [String]) -> Int32 {
        // `--settings <path>` aims at another file. Needed because
        // `NSHomeDirectory()` ignores `$HOME`, so there is otherwise no way to
        // rehearse this against anything but the user's real settings.
        var writer = ClaudeSettingsWriter()
        if let index = arguments.firstIndex(of: "--settings"), index + 1 < arguments.count {
            writer = ClaudeSettingsWriter(path: arguments[index + 1])
        }
        let installer = HookInstaller(writer: writer)
        let uninstalling = arguments.contains("--uninstall-hook")
        let assumeYes = arguments.contains("--yes") || arguments.contains("-y")

        let before: OrderedJSON
        do { before = try installer.writer.read() }
        catch {
            FileHandle.standardError.write(Data(
                "vibebuddy : \(installer.writer.path) illisible — \(error)\n".utf8))
            return 1
        }

        let after = uninstalling
            ? HookInstaller.removing(before)
            : installer.preview(before)

        guard after != before else {
            print(uninstalling
                ? "Rien à retirer : aucun hook VibeBuddy dans \(installer.writer.path)."
                : "Déjà installé, rien à écrire. \(installer.writer.path) est inchangé.")
            return 0
        }

        if !uninstalling {
            guard FileManager.default.isExecutableFile(atPath: installer.hookPath) else {
                FileHandle.standardError.write(Data(
                    "vibebuddy : \(installer.hookPath) introuvable ou non exécutable.\n".utf8))
                return 1
            }
        }

        print(uninstalling ? "Retrait du hook de :" : "Installation du hook dans :")
        print("  \(installer.writer.path)\n")
        print(TextDiff.unified(before.encoded(), after.encoded()))
        print("\nUne sauvegarde horodatée est prise avant écriture, dans :")
        print("  \(installer.writer.backupDirectory)")

        guard assumeYes || confirm() else {
            print("Annulé. Rien n'a été écrit.")
            return 1
        }

        do {
            let changed = uninstalling ? try installer.uninstall() : try installer.install()
            print(changed ? "Écrit." : "Rien à écrire.")
            return 0
        } catch {
            FileHandle.standardError.write(Data("vibebuddy : échec — \(error)\n".utf8))
            return 1
        }
    }

    private static func confirm() -> Bool {
        print("\nÉcrire ? [o/N] ", terminator: "")
        guard let line = readLine() else { return false }
        return ["o", "oui", "y", "yes"].contains(line.lowercased())
    }
}

/// Just enough diff to show what a write would do.
///
/// A hundred lines of LCS beats asking the user to trust a summary of a change
/// to their own file. Not a general-purpose tool: it prints whole lines, has no
/// options, and exists for one screen of output.
enum TextDiff {

    static func unified(_ old: String, _ new: String, context: Int = 3) -> String {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        let edits = diff(a, b)

        // Which lines to print: every change, plus `context` lines either side.
        var interesting = Set<Int>()
        for (index, edit) in edits.enumerated() where edit.kind != .same {
            for offset in max(0, index - context)...min(edits.count - 1, index + context) {
                interesting.insert(offset)
            }
        }
        guard !interesting.isEmpty else { return "  (aucune différence)" }

        var out: [String] = []
        var skipping = false
        for (index, edit) in edits.enumerated() {
            guard interesting.contains(index) else {
                if !skipping { out.append("  …"); skipping = true }
                continue
            }
            skipping = false
            switch edit.kind {
            case .same:    out.append("   \(edit.text)")
            case .removed: out.append("  -\(edit.text)")
            case .added:   out.append("  +\(edit.text)")
            }
        }
        return out.joined(separator: "\n")
    }

    struct Edit { enum Kind { case same, removed, added }; let kind: Kind; let text: String }

    /// Longest common subsequence, walked back into edits.
    static func diff(_ a: [String], _ b: [String]) -> [Edit] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var out: [Edit] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                out.append(Edit(kind: .same, text: a[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                out.append(Edit(kind: .removed, text: a[i])); i += 1
            } else {
                out.append(Edit(kind: .added, text: b[j])); j += 1
            }
        }
        while i < a.count { out.append(Edit(kind: .removed, text: a[i])); i += 1 }
        while j < b.count { out.append(Edit(kind: .added, text: b[j])); j += 1 }
        return out
    }
}
