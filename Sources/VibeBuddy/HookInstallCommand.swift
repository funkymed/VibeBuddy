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
