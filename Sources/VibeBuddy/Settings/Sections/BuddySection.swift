import AppKit
import SwiftUI
import VibeBuddyKit

/// Choose a buddy, and edit every one of its expressions.
///
/// # The layer, not the file
///
/// Edits go to `BuddyOverrides` in preferences; the `.buddy` file is never
/// written. That was arbitrated on 2026-08-20 (RFC-010 §3) and it costs
/// something real — an edit no longer travels with the file — which is why
/// `Exporter` exists two rows below.
///
/// # Live, or it is not an editor
///
/// Every change re-resolves the manifest and pushes it to the notch, so the
/// buddy on screen is the buddy being edited. An editor whose result only shows
/// after a relaunch is a text field with extra steps.
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
                preview(manifest)
                expressionPicker(manifest)
                ExpressionEditorView(
                    l10n: l10n, appearance: appearance,
                    manifest: manifest, expression: selectedExpression,
                    onChange: { onBuddyChange(appearance.buddyID) })
                actions(manifest)
            }
            if let note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(s.buddyFolder)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: reload)
    }

    // MARK: - Pieces

    private var picker: some View {
        SettingsGroup(title: s.activeBuddy) {
            SettingsRow(title: s.activeBuddy) {
                Picker("", selection: Binding(
                    get: { appearance.buddyID },
                    set: { appearance.buddyID = $0; onBuddyChange($0) }
                )) {
                    ForEach(available, id: \.id) { manifest in
                        Text(manifest.name).tag(manifest.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
        }
    }

    /// Through `BuddyView`, like everywhere else: an editor previewing its
    /// subject with a different renderer is previewing something the app never
    /// shows. This is the one place the animation budget runs `lively` — the
    /// speed field cannot be judged from a still frame.
    private func preview(_ manifest: BuddyManifest) -> some View {
        HStack(spacing: 18) {
            ForEach(declared(in: manifest), id: \.self) { expression in
                BuddyView(
                    manifest: manifest, expression: expression,
                    budget: BuddyEditorBudget.shared, pixelSize: appearance.pixelSize)
                    .fixedSize()
                    .opacity(expression == selectedExpression ? 1 : 0.45)
                    .onTapGesture { selectedExpression = expression }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black))
    }

    private func expressionPicker(_ manifest: BuddyManifest) -> some View {
        Picker("", selection: $selectedExpression) {
            ForEach(declared(in: manifest), id: \.self) { expression in
                Text(label(for: expression, manifest: manifest)).tag(expression)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private func actions(_ manifest: BuddyManifest) -> some View {
        HStack(spacing: 10) {
            Button(s.duplicate) { duplicate(manifest) }
            Button(s.export) { export(manifest) }
            Spacer()
            if appearance.overrides.hasEdits(for: manifest.id) {
                Button(s.resetBuddy, role: .destructive) {
                    appearance.overrides.resetAll(of: manifest.id)
                    onBuddyChange(appearance.buddyID)
                }
            }
            if appearance.overrides.created[manifest.id] != nil {
                Button(s.deleteBuddy, role: .destructive) { delete(manifest) }
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        var found = BuddyLoader.available()
        // Buddies created in the app have no file, so the loader cannot see
        // them. They are appended here rather than taught to the loader: the
        // loader's job is the disk, and giving it a second source would put the
        // merge rule in two places.
        for id in appearance.overrides.created.keys.sorted() {
            if let manifest = appearance.overrides.manifest(forCreated: id) {
                found.append(manifest)
            }
        }
        available = found
    }

    /// Duplicating copies the *resolved* manifest — file plus edits — because
    /// that is what the user sees and therefore what they mean by "this one".
    private func duplicate(_ manifest: BuddyManifest) {
        let id = uniqueID(from: manifest.id)
        var created = BuddyOverrides.Created(
            name: "\(manifest.name) 2", colour: manifest.colour,
            fontSize: Double(manifest.fontSize),
            framesPerSecond: manifest.framesPerSecond, font: manifest.font)
        for (name, expression) in manifest.expressions {
            created.expressions[name] = BuddyOverrides.Expression(
                frames: expression.frames, colour: expression.colour,
                fontSize: expression.fontSize.map { Double($0) },
                framesPerSecond: expression.framesPerSecond, motion: expression.motion)
        }
        appearance.overrides.created[id] = created
        reload()
        appearance.buddyID = id
        onBuddyChange(id)
    }

    private func delete(_ manifest: BuddyManifest) {
        appearance.overrides.created.removeValue(forKey: manifest.id)
        appearance.overrides.resetAll(of: manifest.id)
        reload()
        appearance.buddyID = available.first?.id ?? BuiltInBuddy.id
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
/// A separate instance from the app's: the pill's budget follows visibility and
/// activity, and borrowing it here would either freeze the preview or keep the
/// notch animating because a window is open somewhere.
@MainActor
enum BuddyEditorBudget {
    static let shared: AnimationBudget = {
        let budget = AnimationBudget()
        budget.set(.lively)
        return budget
    }()
}
