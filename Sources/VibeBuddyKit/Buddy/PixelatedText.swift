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

    /// Draw the glyphs into a deliberately small bitmap.
    ///
    /// **Not `ImageRenderer`.** It produces the same picture and costs ~80 MB of
    /// physical footprint the first time it runs: measured 2026-08-20, the app
    /// sat at 101 MB with it and 21 MB without, against a 40 MB budget. It
    /// starts a SwiftUI rendering pipeline to draw a dozen glyphs.
    ///
    /// `NSAttributedString` into an `NSBitmapImageRep` gives the same
    /// nearest-neighbour source: measure the text at its real size, allocate a
    /// bitmap of `size / pixelSize` device pixels, and scale the drawing down
    /// into it. The image keeps its natural point size, so the layout is
    /// unchanged and only the number of pixels behind it drops.
    private func rasterise() {
        guard renderedKey != key, !text.isEmpty else { return }

        let font = nsFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            // White, tinted later: the image ships as a template so a colour
            // change never re-rasterises.
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let natural = string.size()
        let width = max(1, Int((natural.width / pixelSize).rounded(.up)))
        let height = max(1, Int((natural.height / pixelSize).rounded(.up)))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.scaleBy(x: 1 / pixelSize, y: 1 / pixelSize)
        string.draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: natural)
        image.addRepresentation(rep)
        image.isTemplate = true
        rendered = image
        renderedKey = key
    }

    /// The font the bitmap is drawn in — the same one `resolvedFont` names.
    private var nsFont: NSFont {
        if let font, let named = NSFont(name: font, size: fontSize) { return named }
        return NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }
}
