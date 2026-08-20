import SwiftUI
import VibeBuddyKit

/// One expression: the two things the settings can change without editing the
/// `.buddy` file itself.
///
/// The pose — shapes, sizes, tempo — lives in the file. It is a dozen numbers
/// per face and a form for it would be a form for a text format that is already
/// readable; `--info` previews it, and the file reloads on save.
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
            attributes
        }
    }

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
                    .pointingHandCursor()
                }
            }
        }
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
