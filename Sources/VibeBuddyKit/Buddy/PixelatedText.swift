import SwiftUI

/// Text rendered as chunky pixels.
///
/// # Why a bitmap detour
///
/// Nothing in SwiftUI quantises text. `Canvas` rasterises after its transform,
/// so scaling up inside one produces smooth glyphs at the final resolution;
/// `.drawingGroup()` rasterises at native scale. Both give a bigger smooth face,
/// not a blockier one.
///
/// The only way to get real pixels is to rasterise **small** and enlarge with
/// nearest-neighbour sampling. `ImageRenderer` at a fractional scale gives the
/// small bitmap; `.interpolation(.none)` refuses to smooth it on the way back up.
///
/// # And why it is cheap anyway
///
/// Rasterising per frame would be wasteful, so the bitmap is cached and only
/// rebuilt when the text, colour or size changes — at most once a second, since
/// that is the animation's own rate. The motion on top (scale, offset) applies
/// to the cached image and costs nothing.
@MainActor
struct PixelatedText: View {

    let text: String
    let colour: Color
    let fontSize: CGFloat
    /// Device pixels per rendered pixel. Higher is blockier.
    let pixelSize: CGFloat
    /// Family, or nil for the system font.
    let font: String?

    @State private var rendered: NSImage?
    @State private var renderedKey: String = ""

    private var key: String { "\(text)|\(fontSize)|\(pixelSize)|\(font ?? "")" }

    var body: some View {
        Group {
            if let rendered {
                Image(nsImage: rendered)
                    // The whole point: no smoothing on the way back up.
                    .interpolation(.none)
                    .resizable()
                    // Natural size, *not* multiplied by `pixelSize`.
                    //
                    // `ImageRenderer` already reports its result in points; the
                    // scale only changes how many device pixels back them. An
                    // earlier version multiplied here and drew the face two to
                    // three times too large — overflowing the slot `PillLayout`
                    // had measured for it.
                    //
                    // The blockiness comes from the bitmap being *coarser* than
                    // the display, not from the view being bigger.
                    .frame(width: rendered.size.width, height: rendered.size.height)
                    // Tinting the bitmap rather than baking the colour in means
                    // a colour change costs nothing — no re-rasterise.
                    .foregroundStyle(colour)
            } else {
                // First frame, before the bitmap exists. Drawn plainly rather
                // than left blank, so the buddy never flickers into existence.
                plainText
            }
        }
        .onAppear(perform: rasterise)
        .onChange(of: key) { rasterise() }
    }

    private var plainText: some View {
        Text(text)
            .font(resolvedFont)
            .foregroundStyle(colour)
            .fixedSize()
    }

    /// The requested family if it exists, the system font otherwise.
    ///
    /// A named font that is not installed must not silently become something
    /// unrelated — `Font.custom` falls back on its own, so the existence check
    /// is what keeps the failure visible in diagnostics instead.
    private var resolvedFont: Font {
        if let font, NSFont(name: font, size: fontSize) != nil {
            return .custom(font, size: fontSize)
        }
        return .system(size: fontSize, weight: .medium)
    }

    private func rasterise() {
        guard renderedKey != key else { return }
        let renderer = ImageRenderer(content:
            Text(text)
                .font(resolvedFont)
                // Rendered as a white mask; the colour is applied to the image
                // afterwards as a template.
                .foregroundStyle(.white)
                .fixedSize()
        )
        // Below one, this is what shrinks the bitmap — the source of the
        // blockiness once it is scaled back up.
        renderer.scale = 1 / pixelSize
        renderer.isOpaque = false

        guard let image = renderer.nsImage else { return }
        image.isTemplate = true      // so `foregroundStyle` tints it
        rendered = image
        renderedKey = key
    }
}
