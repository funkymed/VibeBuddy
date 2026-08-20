import AppKit
import SwiftUI
import VibeBuddyKit

/// Choose a buddy, and edit every one of its expressions.
///
/// See RFC-010, "Notes d'implémentation".
struct BuddySection: View {
    @Bindable var l10n: Localisation
    @Bindable var appearance: AppearancePrefs
    let onBuddyChange: (String?) -> Void

    @State private var available: [BuddyManifest] = []
    @State private var selectedExpression: BuddyExpression = .idle
    @State private var note: String?

    private var s: SettingsStrings { l10n.settings }

    /// The manifest as the user has it: file, then layer.
    private var manifest: BuddyManifest? {
        guard let base = available.first(where: { $0.id == appearance.buddyID })
        else { return nil }
        return appearance.resolved(base)
    }

    var body: some View {
        SettingsPage {
            picker
            if let manifest {
                BuddyPreviewStrip(
                    manifest: manifest, expressions: declared(in: manifest),
                    pixelSize: appearance.pixelSize, selection: $selectedExpression)
                expressionPicker(manifest)
                ExpressionEditorView(
                    l10n: l10n, appearance: appearance,
                    manifest: manifest, expression: selectedExpression,
                    onChange: { onBuddyChange(appearance.buddyID) })
                BuddyActionsRow(
                    strings: s,
                    hasEdits: appearance.overrides.hasEdits(for: manifest.id),
                    isCreated: appearance.overrides.created[manifest.id] != nil,
                    onDuplicate: { duplicate(manifest) },
                    onExport: { export(manifest) },
                    onReset: { reset(manifest) },
                    onDelete: { delete(manifest) })
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Text(s.buddyFolder)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Pieces

    private var picker: some View {
        SettingsGroup(title: s.activeBuddy) {
            SettingsRow(title: s.activeBuddy) {
                Picker(s.activeBuddy, selection: $appearance.buddyID) {
                    ForEach(available, id: \.id) { manifest in
                        Text(manifest.name).tag(manifest.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: appearance.buddyID) { onBuddyChange(appearance.buddyID) }
            }
        }
    }

    private func expressionPicker(_ manifest: BuddyManifest) -> some View {
        Picker(s.expressions, selection: $selectedExpression) {
            ForEach(declared(in: manifest), id: \.self) { expression in
                Text(label(for: expression, manifest: manifest)).tag(expression)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    // MARK: - Actions

    private func reload() {
        var found = BuddyLoader.available()
        // Buddies created in the app have no file, so the loader cannot see them.
        for id in appearance.overrides.created.keys.sorted() {
            if let manifest = appearance.overrides.manifest(forCreated: id) {
                found.append(manifest)
            }
        }
        available = found
    }

    /// Duplicates the *resolved* manifest: file plus edits.
    private func duplicate(_ manifest: BuddyManifest) {
        let id = uniqueID(from: manifest.id)
        var created = BuddyOverrides.Created(
            name: "\(manifest.name) 2", colour: manifest.colour, face: manifest.face)
        for (name, expression) in manifest.expressions {
            created.expressions[name] = BuddyOverrides.Expression(
                colour: expression.colour, eye: expression.eye, motion: expression.motion)
        }
        appearance.overrides.created[id] = created
        reload()
        // Do not call `onBuddyChange` here: the id moves, so the picker's
        // `onChange` already fires and the buddy would reload twice.
        appearance.buddyID = id
    }

    private func delete(_ manifest: BuddyManifest) {
        appearance.overrides.created.removeValue(forKey: manifest.id)
        appearance.overrides.resetAll(of: manifest.id)
        reload()
        appearance.buddyID = available.first?.id ?? BuiltInBuddy.id
    }

    /// Drops the whole override layer. The id does not move, so the redraw has
    /// to be asked for here.
    private func reset(_ manifest: BuddyManifest) {
        appearance.overrides.resetAll(of: manifest.id)
        onBuddyChange(appearance.buddyID)
    }

    private func export(_ manifest: BuddyManifest) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(manifest.id).buddy"
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch BuddyExportWriter.write(manifest, to: url.path, overwrite: true) {
        case let .success(path): note = s.exported(path)
        case let .failure(error): note = s.exportFailed(error.description)
        }
    }

    // MARK: - Helpers

    private func declared(in manifest: BuddyManifest) -> [BuddyExpression] {
        BuddyExpression.allCases.filter { manifest.expressions[$0.rawValue] != nil }
    }

    private func label(for expression: BuddyExpression, manifest: BuddyManifest) -> String {
        let edited = appearance.overrides.expression(expression.rawValue, of: manifest.id) != nil
        return expression.rawValue + (edited ? " ●" : "")
    }

    private func uniqueID(from base: String) -> String {
        var candidate = "\(base)-copie"
        var index = 2
        let taken = Set(available.map(\.id))
        while taken.contains(candidate) {
            candidate = "\(base)-copie-\(index)"
            index += 1
        }
        return candidate
    }
}

/// The editor's own animation budget, held at `lively`.
///
/// Keep it separate from the pill's: sharing one either freezes the preview or
/// keeps the notch animating because a window is open somewhere.
@MainActor
enum BuddyEditorBudget {
    static let shared: AnimationBudget = {
        let budget = AnimationBudget()
        budget.set(.lively)
        return budget
    }()
}
