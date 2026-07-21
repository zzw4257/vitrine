// Renders the Vitrine app icon (glass prism on aurora) into an .iconset directory.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func draw(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let r = CGRect(x: 0, y: 0, width: size, height: size)

    // macOS squircle inset (~10%)
    let inset = size * 0.09
    let card = r.insetBy(dx: inset, dy: inset)
    let path = CGPath(roundedRect: card, cornerWidth: card.width * 0.225, cornerHeight: card.width * 0.225, transform: nil)
    ctx.addPath(path); ctx.clip()

    // Deep space base
    let base = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(calibratedRed: 0.07, green: 0.06, blue: 0.14, alpha: 1).cgColor,
                 NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.07, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // Aurora blobs
    func blob(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, _ color: NSColor) {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy), endRadius: radius, options: [])
    }
    blob(size * 0.28, size * 0.72, size * 0.55, NSColor(calibratedRed: 0.49, green: 0.36, blue: 1.0, alpha: 1))
    blob(size * 0.78, size * 0.30, size * 0.50, NSColor(calibratedRed: 0.18, green: 0.83, blue: 0.75, alpha: 1))
    blob(size * 0.72, size * 0.82, size * 0.40, NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.55, alpha: 1))

    // Glass prism: triangle with translucent fill + bright edges
    let cx = size * 0.5, cy = size * 0.47, s = size * 0.30
    let top = CGPoint(x: cx, y: cy + s)
    let left = CGPoint(x: cx - s * 0.95, y: cy - s * 0.75)
    let right = CGPoint(x: cx + s * 0.95, y: cy - s * 0.75)
    let tri = CGMutablePath()
    tri.move(to: top); tri.addLine(to: left); tri.addLine(to: right); tri.closeSubpath()

    ctx.saveGState()
    ctx.addPath(tri); ctx.clip()
    let glass = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(calibratedWhite: 1, alpha: 0.34).cgColor,
                 NSColor(calibratedWhite: 1, alpha: 0.08).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glass, start: top, end: CGPoint(x: cx, y: cy - s * 0.75), options: [])
    ctx.restoreGState()

    ctx.addPath(tri)
    ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.9).cgColor)
    ctx.setLineWidth(max(1, size * 0.012))
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Refracted beam exiting the prism
    let beam = CGMutablePath()
    beam.move(to: CGPoint(x: cx + s * 0.2, y: cy - s * 0.1))
    beam.addLine(to: CGPoint(x: size * 0.86, y: cy + s * 0.55))
    beam.addLine(to: CGPoint(x: size * 0.86, y: cy - s * 0.35))
    beam.closeSubpath()
    ctx.saveGState()
    ctx.addPath(beam); ctx.clip()
    let spectrum = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(calibratedRed: 1, green: 0.62, blue: 0.42, alpha: 0.9).cgColor,
                 NSColor(calibratedRed: 0.4, green: 0.95, blue: 0.8, alpha: 0.75).cgColor,
                 NSColor(calibratedRed: 0.55, green: 0.5, blue: 1, alpha: 0.55).cgColor] as CFArray,
        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(spectrum,
        start: CGPoint(x: cx, y: cy + s * 0.4), end: CGPoint(x: cx, y: cy - s * 0.5), options: [])
    ctx.restoreGState()

    // Top sheen
    ctx.addPath(path)
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(calibratedWhite: 1, alpha: 0.22).cgColor,
                 NSColor(calibratedWhite: 1, alpha: 0).cgColor] as CFArray, locations: [0, 0.35])!
    ctx.clip()
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    img.unlockFocus()
    return img
}

let specs: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    let img = draw(px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("icons → \(outDir)")
