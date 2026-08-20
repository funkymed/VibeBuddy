// generate-icon.swift — draw the app icon into an .iconset, no binary assets.
//
// The buddy is the product's face, so the icon is the buddy: a rounded black
// tile with the pill's own glow. Drawn rather than shipped, so a colour change
// is a diff and not a binary blob.
//
//   swift scripts/generate-icon.swift <output.iconset>

import AppKit
import Foundation

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "dist/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: output, withIntermediateDirectories: true)

/// The icon at one size. macOS asks for ten of them.
func draw(size: Int) -> Data? {
    let side = CGFloat(size)
    // A bitmap rep with an explicit context, not `NSImage.lockFocus`: focusing
    // an image needs a window server session and fails outright from a script
    // ("CGImageDestinationFinalize failed for public.tiff").
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's grid: the artwork occupies about 80 % of the tile, centred.
    let inset = side * 0.10
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let tile = NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22)
    NSColor.black.setFill()
    tile.fill()

    // Three dots, the way the pill shows a buddy at rest.
    let dot = side * 0.085
    let gap = side * 0.055
    let total = dot * 3 + gap * 2
    var x = rect.midX - total / 2
    let y = rect.midY - dot / 2
    for shade in [NSColor.systemBlue, .systemBlue, .systemBlue] {
        let circle = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot))
        shade.withAlphaComponent(0.95).setFill()
        circle.fill()
        x += dot + gap
    }

    return rep.representation(using: .png, properties: [:])
}

// The ten entries `iconutil` expects, name included.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for entry in sizes {
    guard let data = draw(size: entry.pixels) else {
        FileHandle.standardError.write(Data("échec du rendu \(entry.name)\n".utf8))
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: "\(output)/\(entry.name).png"))
}

print("\(sizes.count) tailles dans \(output)")
