import SwiftUI
import VibeBuddyKit

/// The exact diff of `~/.claude/settings.json`, and nothing written until « Écrire ».
struct HookConsentSheet: View {
    let removing: Bool
    let s: SettingsStrings
    let onDone: () -> Void

    /// What the file would become, as shown. Compared again before writing.
    @State private var shown: OrderedJSON?
    @State private var diff = ""
    @State private var message: String?
    @State private var loaded = false
    @State private var busy = false

    private let installer = HookInstaller()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(removing ? s.hookSheetRemove : s.hookSheetInstall)
                .font(.headline)
            labelled(s.hookSheetFile, installer.writer.path)
            ScrollView([.vertical, .horizontal]) {
                Text(diff)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 220, maxHeight: 360)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
            labelled(s.hookSheetBackup, installer.writer.backupDirectory)
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(s.hookCancel, action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button(s.hookWrite, action: write)
                    .disabled(shown == nil || busy)
            }
        }
        .padding(20)
        .frame(width: 620)
        .task { await load() }
    }

    private func labelled(_ label: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func load() async {
        let result = await Self.pending(installer, removing: removing)
        apply(result)
        loaded = true
    }

    private func apply(_ result: Result<(before: OrderedJSON, after: OrderedJSON)?, Error>) {
        switch result {
        case let .success(pair?):
            shown = pair.after
            diff = TextDiff.unified(pair.before.encoded(), pair.after.encoded())
        case .success(nil):
            shown = nil
            diff = ""
            message = s.hookSheetNothing
        case let .failure(error):
            shown = nil
            message = s.hookSheetFailed("\(error)")
        }
    }

    /// The diff is recomputed here, not reused: a file edited since the sheet opened
    /// would otherwise get a write nobody saw.
    private func write() {
        busy = true
        let installer = installer, removing = removing, expected = shown
        Task {
            let now = await Self.pending(installer, removing: removing)
            if case let .success(pair) = now, pair?.after != expected {
                apply(now)
                message = s.hookSheetChanged
                busy = false
                return
            }
            let outcome: Result<Bool, Error> = await Task.detached(priority: .userInitiated) {
                Result { removing ? try installer.uninstall() : try installer.install() }
            }.value
            busy = false
            switch outcome {
            case .success:
                NotificationCenter.default.post(name: .hookInstallChanged, object: nil)
                onDone()
            case let .failure(error):
                message = s.hookSheetFailed("\(error)")
            }
        }
    }

    private static func pending(_ installer: HookInstaller, removing: Bool) async
        -> Result<(before: OrderedJSON, after: OrderedJSON)?, Error> {
        await Task.detached(priority: .userInitiated) {
            Result { try installer.pendingDiff(removing: removing) }
        }.value
    }
}
