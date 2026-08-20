import SwiftUI
import VibeBuddyKit

/// One expression: its frames, and the four things the format lets it override.
///
/// See RFC-010, "Notes d'implémentation".
struct ExpressionEditorView: View {
    @Bindable var l10n: Localisation
    @Bindable var appearance: AppearancePrefs
    let manifest: BuddyManifest
    let expression: BuddyExpression
    /// Called after every edit so the notch re-renders while it is being made.
    let onChange: () -> Void

    private var s: SettingsStrings { l10n.settings }

    private var settings: BuddyManifest.Expression? {
        manifest.expressions[expression.rawValue]
    }

    private var edit: BuddyOverrides.Expression {
        appearance.overrides.expression(expression.rawValue, of: manifest.id)
            ?? BuddyOverrides.Expression()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            frames
            attributes
        }
    }

    // MARK: - Frames

    private var frames: some View {
        SettingsGroup(title: s.frames) {
            ForEach(Array(currentFrames.enumerated()), id: \.offset) { index, frame in
                HStack(spacing: 8) {
                    TextField("", text: Binding(
                        get: { frame },
                        set: { update(frame: $0, at: index) }))
                        .textFieldStyle(.plain)
                        .font(.body.monospaced())
                    Button {
                        remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(currentFrames.count <= 1)
                    .help(s.removeFrame)
                    Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(index == currentFrames.count - 1)
                }
                .padding(.vertical, 6)
                if index < currentFrames.count - 1 { Divider() }
            }
            Divider()
            Button(s.addFrame) { addFrame() }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.vertical, 8)
        }
    }

    private var currentFrames: [String] {
        edit.frames ?? settings?.frames ?? [""]
    }

    private func update(frame text: String, at index: Int) {
        var frames = currentFrames
        guard frames.indices.contains(index) else { return }
        frames[index] = text
        commit { $0.frames = frames }
    }

    private func addFrame() {
        var frames = currentFrames
        frames.append(frames.last ?? "")
        commit { $0.frames = frames }
    }

    private func remove(at index: Int) {
        var frames = currentFrames
        guard frames.count > 1, frames.indices.contains(index) else { return }
        frames.remove(at: index)
        commit { $0.frames = frames }
    }

    private func move(_ index: Int, by offset: Int) {
        var frames = currentFrames
        let target = index + offset
        guard frames.indices.contains(index), frames.indices.contains(target) else { return }
        frames.swapAt(index, target)
        commit { $0.frames = frames }
    }

    // MARK: - Attributes

    private var attributes: some View {
        SettingsGroup(title: expression.rawValue) {
            SettingsRow(title: s.colour, hint: edit.colour == nil ? s.inherited : nil) {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: edit.colour ?? settings?.colour ?? manifest.colour) ?? .white },
                    set: { colour in commit { $0.colour = colour.hexString } }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            Divider()
            SettingsRow(title: s.size, hint: edit.fontSize == nil ? s.inherited : nil) {
                Stepper(
                    value: Binding(
                        get: { edit.fontSize ?? Double(manifest.size(for: settings)) },
                        set: { value in commit { $0.fontSize = value } }),
                    in: 6...48, step: 1
                ) {
                    Text("\(Int(edit.fontSize ?? Double(manifest.size(for: settings))))")
                        .font(.callout.monospaced())
                }
            }
            Divider()
            SettingsRow(title: s.speed, hint: edit.framesPerSecond == nil ? s.inherited : nil) {
                Stepper(
                    value: Binding(
                        get: { edit.framesPerSecond ?? manifest.rate(for: settings) },
                        set: { value in commit { $0.framesPerSecond = value } }),
                    in: BuddyManifest.minimumFrameRate...BuddyManifest.maximumFrameRate,
                    step: 0.5
                ) {
                    Text(rateLabel)
                        .font(.callout.monospaced())
                }
            }
            Divider()
            SettingsRow(title: s.motion, hint: edit.motion == nil ? s.inherited : nil) {
                Picker("", selection: Binding(
                    // Spell out `MotionKind.none`: bare `.none` binds to
                    // `Optional<MotionKind>.none`, the selection is then typed
                    // `MotionKind?`, matches no tag, and the menu shows empty.
                    get: { edit.motion ?? settings?.motion ?? MotionKind.none },
                    set: { value in commit { $0.motion = value } }
                )) {
                    ForEach(MotionKind.allCases, id: \.self) { motion in
                        Text(motion.rawValue).tag(motion)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            if !edit.isEmpty {
                Divider()
                SettingsRow(title: s.resetExpression) {
                    Button(s.resetExpression, role: .destructive) {
                        appearance.overrides.reset(expression.rawValue, of: manifest.id)
                        onChange()
                    }
                }
            }
        }
    }

    private var rateLabel: String {
        let value = edit.framesPerSecond ?? manifest.rate(for: settings)
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// One write path for every field, so a change can never bypass either the
    /// store or the redraw.
    private func commit(_ change: (inout BuddyOverrides.Expression) -> Void) {
        var updated = edit
        change(&updated)
        appearance.overrides.set(updated, for: expression.rawValue, of: manifest.id)
        onChange()
    }
}

extension Color {
    /// `#RRGGBB`, for storing a picked colour in the `.buddy` vocabulary.
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
