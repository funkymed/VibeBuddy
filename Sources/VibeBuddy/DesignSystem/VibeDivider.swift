import SwiftUI

/// A separator, drawn as a line rather than as a `Divider`.
///
/// **`Divider().overlay(colour)` does not do what it looks like.** A `Divider`
/// already paints itself in a system grey, and an overlay in a translucent
/// colour lands *on top* of that grey rather than replacing it. Measured on the
/// real panel: the separator came out at `(26,30,39)` where the reference
/// design has `(11,16,24)` — three times too light, and no amount of lowering
/// the token was ever going to fix it, because the token was not what was being
/// drawn. Two rounds of « still too bright » were spent on that.
///
/// A `Rectangle` of one point, filled with the token, is what the token says.
struct VibeDivider: View {
    var body: some View {
        Rectangle()
            .fill(VibeTheme.Border.divider)
            .frame(height: VibeTheme.Border.width)
    }
}
