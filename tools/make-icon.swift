import Cocoa

// Generates ahdishot's app icon from scratch (no Xcode, no external art): a rounded-rect squircle
// with a blue→purple gradient and a white `camera.viewfinder` SF Symbol — the same motif as the
// menu-bar icon, so the app reads coherently. This is an original placeholder (SF Symbol on custom
// art, per REQUIREMENTS §11 / "no Lightshot assets"); commission bespoke artwork before any release.
//
// Usage:  swift tools/make-icon.swift <output.iconset-dir>
//   then: iconutil -c icns <dir> -o Resources/AppIcon.icns

// A running NSApplication makes SF Symbol lookup reliable from a plain tool.
_ = NSApplication.shared

/// Tints a (template) symbol image to a solid color by filling only where the glyph is opaque.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: image.size))
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

/// Draws the icon into the current graphics context at the given canvas size (points == pixels here).
func drawIcon(size s: CGFloat) {
    // Rounded-rect plate with the transparent margin macOS app icons expect.
    let margin = s * 0.085
    let plate = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = plate.width * 0.225
    let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.52, blue: 0.98, alpha: 1), // blue (top)
        NSColor(srgbRed: 0.38, green: 0.27, blue: 0.87, alpha: 1), // purple (bottom)
    ])!
    gradient.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .semibold)
    guard let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    let white = tinted(symbol, .white)
    let symSize = white.size
    let symRect = NSRect(x: (s - symSize.width) / 2, y: (s - symSize.height) / 2,
                         width: symSize.width, height: symSize.height)
    white.draw(in: symRect)
}

/// Renders the icon to a PNG at an exact pixel size (no screen-scale surprises).
func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <output.iconset-dir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// (filename, pixel size) for every slot iconutil expects.
let slots: [(String, Int)] = [
    ("icon_16x16.png", 16),   ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),   ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in slots {
    try renderPNG(pixels: px).write(to: outDir.appendingPathComponent(name))
    print("  \(name) (\(px)px)")
}
print("Wrote \(slots.count) slots to \(outDir.path)")
