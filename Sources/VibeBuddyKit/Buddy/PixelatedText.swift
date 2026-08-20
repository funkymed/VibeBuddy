import SwiftUI

/// Text rendered as chunky pixels. Nothing in SwiftUI quantises text: the only
/// way to get real pixels is to rasterise **small** and enlarge without
/// smoothing — `ImageRenderer` at a fractional scale, then `.interpolation(.none)`.
/// See RFC-005, "Notes d'implémentation".
@MainActor
struct PixelatedText: View {

    let text: String
    let colour: Color
    let fontSize: CGFloat
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
                    .interpolation(.none)
                    .resizable()
                    // Natural size, *not* multiplied by `pixelSize`:
                    // `ImageRenderer` reports in points. Multiplying here made
                    // the face overflow the slot `PillLayout` measured for it.
                    .frame(width: rendered.size.width, height: rendered.size.height)
                    .foregroundStyle(colour)
            } else {
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

    /// The requested family if it exists, the system font otherwise:
    /// `Font.custom` falls back silently, the check keeps the failure visible.
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
                .foregroundStyle(.white)
                .fixedSize()
        )
        renderer.scale = 1 / pixelSize
        renderer.isOpaque = false

        guard let image = renderer.nsImage else { return }
        image.isTemplate = true      // so `foregroundStyle` tints it
        rendered = image
        renderedKey = key
    }
}
