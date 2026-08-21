// generate-icon.swift — draw the app icon into an .iconset, no binary assets.
//
// The buddy is the product's face, so the icon is its **gaze**: two eyes on a
// dark screen, one round and one square. Two shapes rather than two of the same
// one, because at 16 px a pair of identical dots is every other icon in the bar,
// and the mismatched pair is a mark you can pick out at a glance.
//
// No wordmark: the app's name was drawn under the eyes for a while and taken
// back out. The Finder already writes it under the icon, and Apple's own
// guidance is against text on a macOS icon — at 16 px it is a smudge.
//
// Drawn rather than shipped, so a colour change is a diff and not a binary blob.
//
//   swift scripts/generate-icon.swift <output.iconset>
//
// The eyes are rasterised into whole cells by the same rule the app uses —
// `EyeRaster.contains` for the shape, `EyeRaster.drawableRadius` for the corner.
// Reimplemented here in six lines rather than linked: this is a script, and a
// script that needs the package built is a script that breaks the build it is
// part of. If the rule changes there, change it here; the test
// `IconRuleTests` in the package fails when the two drift apart.

import AppKit
import Foundation

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "dist/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: output, withIntermediateDirectories: true)

// The two colours the buddy already wears: the blue it finishes in, the green
// it works in. Taken from `eve.buddy` rather than invented, so the icon and the
// face are the same object.
let blue = NSColor(srgbRed: 0.353, green: 0.722, blue: 1.0, alpha: 1)  // #5AB8FF
let green = NSColor(srgbRed: 0.439, green: 0.831, blue: 0.420, alpha: 1) // #70D46B
let screenTop = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
let screenBottom = NSColor(srgbRed: 0.03, green: 0.03, blue: 0.035, alpha: 1)

/// The corner radius this grid can actually draw, in points.
///
/// Mirrors `EyeRaster.drawableRadius`: one whole cell of straight edge on every
/// side, and the radius on a whole number of cells. A round eye four cells
/// across is not a circle, it is a diamond.
func drawableRadius(_ radius: CGFloat, half: CGFloat, pitch: CGFloat) -> CGFloat {
    guard pitch > 0, radius > 0 else { return 0 }
    let straight = half - pitch
    return (min(radius, max(0, straight)) / pitch).rounded(.down) * pitch
}

/// Whether a cell centre falls inside a rounded rectangle. Mirrors the `.oval`
/// branch of `EyeRaster.contains`.
func inside(_ point: CGPoint, centre: CGPoint, half: CGFloat, radius: CGFloat) -> Bool {
    let ax = abs(point.x - centre.x) - (half - radius)
    let ay = abs(point.y - centre.y) - (half - radius)
    if ax <= 0 || ay <= 0 {
        return abs(point.x - centre.x) <= half && abs(point.y - centre.y) <= half
    }
    return ax * ax + ay * ay <= radius * radius
}

/// One eye, drawn as whole cells.
///
/// `radius` is the corner it asks for; the grid decides what it gets. A square
/// eye asks for none, so it gets none at any size.
func drawEye(centre: CGPoint, half: CGFloat, radius: CGFloat, pitch: CGFloat) {
    let drawn = drawableRadius(radius, half: half, pitch: pitch)
    let cells = Int((half * 2 / pitch).rounded())
    let origin = CGPoint(x: centre.x - CGFloat(cells) * pitch / 2,
                         y: centre.y - CGFloat(cells) * pitch / 2)
    // A hairline between cells, so the pixel grid reads as a grid rather than
    // as one solid block. Proportional, so it survives every size.
    let bleed = pitch * 0.08
    for row in 0..<cells {
        for column in 0..<cells {
            let cell = CGRect(
                x: origin.x + CGFloat(column) * pitch,
                y: origin.y + CGFloat(row) * pitch,
                width: pitch, height: pitch)
            guard inside(CGPoint(x: cell.midX, y: cell.midY),
                         centre: centre, half: half, radius: drawn)
            else { continue }
            NSBezierPath(rect: cell.insetBy(dx: bleed, dy: bleed)).fill()
        }
    }
}

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
    NSGradient(starting: screenTop, ending: screenBottom)?.draw(in: tile, angle: -90)

    // Scanlines, the buddy's own screen. Faint enough to be texture rather than
    // stripes, and skipped below 64 px where they would just be noise.
    if size >= 64 {
        NSGraphicsContext.saveGraphicsState()
        tile.setClip()
        NSColor.white.withAlphaComponent(0.035).setFill()
        let step = max(2, side / 64)
        var y = rect.minY
        while y < rect.maxY {
            NSBezierPath(rect: NSRect(x: rect.minX, y: y, width: rect.width, height: step / 2)).fill()
            y += step
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // The eyes. Thirteen cells across at every size the grid can hold them.
    //
    // Nine was tried first and the round one came out a square with its corners
    // nicked: the drawable-radius rule keeps a whole cell of straight edge on
    // each side, which at nine cells leaves a corner too shallow to read. At
    // thirteen the same rule allows five cells of radius, and a circle comes
    // out a circle — which is the whole reason the pair works as a mark.
    let eyeHalf = rect.width * 0.175
    // Close together, and off the same line: the round one sits low, the square
    // one high. A pair centred and evenly spaced is a pair of dots; staggered,
    // it reads as a face looking at something.
    let gap = rect.width * 0.035
    let stagger = eyeHalf * 0.42
    let y = rect.midY
    let cells: CGFloat = 13
    var pitch = eyeHalf * 2 / cells
    // Below two pixels a cell is a smudge. The small sizes drop the grid and
    // draw the two shapes solid — the mark is the pair, not the pixels.
    let celled = pitch >= 2

    let left = CGPoint(x: rect.midX - gap - eyeHalf, y: y - stagger)
    let right = CGPoint(x: rect.midX + gap + eyeHalf, y: y + stagger)

    if celled {
        blue.setFill()
        drawEye(centre: left, half: eyeHalf, radius: eyeHalf, pitch: pitch)
        green.setFill()
        drawEye(centre: right, half: eyeHalf, radius: 0, pitch: pitch)
    } else {
        blue.setFill()
        pitch = 0
        NSBezierPath(ovalIn: NSRect(x: left.x - eyeHalf, y: left.y - eyeHalf,
                                    width: eyeHalf * 2, height: eyeHalf * 2)).fill()
        green.setFill()
        NSBezierPath(rect: NSRect(x: right.x - eyeHalf, y: right.y - eyeHalf,
                                  width: eyeHalf * 2, height: eyeHalf * 2)).fill()
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
