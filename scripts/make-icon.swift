// Draws the app icon and writes Resources/AppIcon.icns and docs/icon.png.
//
//   swift scripts/make-icon.swift                 the built-in design
//   swift scripts/make-icon.swift path/to/art.png  use your own square artwork instead
//
// Built-in design (1024 master on the macOS grid): an 824×824 black body at
// (100, 100) with a 185.4 corner radius, a red glow and rim, and an original pair
// of pro-style in-ear buds (white shell, red ear tips, short stems) drawn from
// paths. SF Symbols can't be used in app icons, so the buds are drawn here.
// Custom artwork is clipped to the same rounded body so it sits on the macOS grid.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let customArt: CGImage? = CommandLine.arguments.dropFirst().first.flatMap { path in
    guard let image = NSImage(contentsOfFile: path) else { fatalError("can't read \(path)") }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// One in-ear bud in a local frame (y down), pro style: a rounded body, an ear
/// tip pointing left and a short stem going down-right. Drawn from paths.
struct BudShape {
    let body = CGPath(ellipseIn: CGRect(x: -125, y: -110, width: 250, height: 220), transform: nil)
    let stem = CGPath(roundedRect: CGRect(x: 20, y: 20, width: 82, height: 250),
                      cornerWidth: 41, cornerHeight: 41, transform: nil)
    /// The silicone tip, an oval on the inner side of the body.
    var tip: CGPath {
        var t = CGAffineTransform(translationX: -118, y: -18).rotated(by: -0.35)
        return CGPath(ellipseIn: CGRect(x: -62, y: -80, width: 124, height: 160), transform: &t)
    }
    var silhouette: CGPath {
        let path = CGMutablePath()
        path.addPath(body)
        path.addPath(stem)
        return path
    }
}

func drawEarbud(_ cg: CGContext, at center: CGPoint, mirrored: Bool, scale: CGFloat = 1) {
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.scaleBy(x: mirrored ? -scale : scale, y: scale)
    cg.rotate(by: 0.10)
    let bud = BudShape()

    // Red ear tip, behind the body.
    cg.saveGState()
    cg.addPath(bud.tip)
    cg.clip()
    let tipGradient = CGGradient(colorsSpace: space, colors: [color(0xFF5A4D), color(0xB3170C)] as CFArray,
                                 locations: [0, 1])!
    cg.drawLinearGradient(tipGradient, start: CGPoint(x: -150, y: -100), end: CGPoint(x: -80, y: 80), options: [])
    cg.restoreGState()
    // Dark core of the tip.
    var coreT = CGAffineTransform(translationX: -150, y: -24).rotated(by: -0.35)
    cg.addPath(CGPath(ellipseIn: CGRect(x: -22, y: -34, width: 44, height: 68), transform: &coreT))
    cg.setFillColor(color(0x5A0A05))
    cg.fillPath()

    // Shadow under the white shell.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 20), blur: 40, color: color(0x000000, 0.6))
    cg.addPath(bud.silhouette)
    cg.setFillColor(color(0xF2F2F4))
    cg.fillPath()
    cg.restoreGState()

    // Glossy white shell.
    cg.saveGState()
    cg.addPath(bud.silhouette)
    cg.clip()
    let shell = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xD5D6DB)] as CFArray,
                           locations: [0, 1])!
    cg.drawLinearGradient(shell, start: CGPoint(x: 0, y: -110), end: CGPoint(x: 0, y: 270), options: [])
    let spec = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.95), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    cg.drawRadialGradient(spec, startCenter: CGPoint(x: 10, y: -60), startRadius: 0,
                          endCenter: CGPoint(x: 10, y: -60), endRadius: 120, options: [])
    // Seam where the stem meets the body.
    cg.setStrokeColor(color(0x000000, 0.08))
    cg.setLineWidth(3)
    cg.addEllipse(in: CGRect(x: -125, y: -110, width: 250, height: 220))
    cg.strokePath()
    cg.restoreGState()

    // Sensor: a small dark oval near the top, and the red stem tip.
    cg.setFillColor(color(0x1C1C1E))
    cg.fillEllipse(in: CGRect(x: 30, y: -66, width: 46, height: 30))
    cg.setFillColor(color(0xE8392C))
    cg.fillEllipse(in: CGRect(x: 43, y: 226, width: 36, height: 36))

    cg.addPath(bud.silhouette)
    cg.setStrokeColor(color(0x000000, 0.12))
    cg.setLineWidth(3)
    cg.strokePath()
    cg.restoreGState()
}

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = ctx.cgContext
    let s = CGFloat(pixels) / 1024
    // Work in 1024 units with y pointing down.
    cg.translateBy(x: 0, y: CGFloat(pixels))
    cg.scaleBy(x: s, y: -s)
    cg.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185.4, cornerHeight: 185.4, transform: nil)

    // Drop shadow (y +10, blur 20, black 30%).
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 20 * s, color: color(0x000000, 0.3))
    cg.addPath(bodyPath)
    cg.setFillColor(color(0x1E1E1F))
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(bodyPath)
    cg.clip()
    if let customArt {
        // Draw the artwork upright inside the body.
        cg.saveGState()
        cg.translateBy(x: 0, y: body.maxY + body.minY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(customArt, in: body)
        cg.restoreGState()
    } else {
        // Black with a red glow rising from the bottom, and a faint top sheen.
        let base = CGGradient(colorsSpace: space, colors: [color(0x161616), color(0x000000)] as CFArray,
                              locations: [0, 1])!
        cg.drawLinearGradient(base, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        let glowRed = CGGradient(colorsSpace: space, colors: [color(0xE8392C, 0.55), color(0xE8392C, 0)] as CFArray,
                                 locations: [0, 1])!
        cg.drawRadialGradient(glowRed, startCenter: CGPoint(x: 512, y: 930), startRadius: 0,
                              endCenter: CGPoint(x: 512, y: 930), endRadius: 470, options: [])
        drawEarbud(cg, at: CGPoint(x: 375, y: 420), mirrored: false, scale: 1.02)
        drawEarbud(cg, at: CGPoint(x: 649, y: 420), mirrored: true, scale: 1.02)
        let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray,
                               locations: [0, 1])!
        cg.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.minY + 420), options: [])
    }
    cg.restoreGState()

    // Specular rim: brighter at the top, like Liquid Glass.
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    cg.replacePathWithStrokedPath()
    cg.clip()
    let rim = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.30), color(0xE8392C, 0.35)] as CFArray,
                         locations: [0, 1])!
    cg.setLineWidth(4)
    cg.drawLinearGradient(rim, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
    cg.restoreGState()

    ctx.flushGraphics()
    return rep
}

func png(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(drawIcon(pixels: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(drawIcon(pixels: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }

try png(drawIcon(pixels: 256), to: root.appendingPathComponent("docs/icon.png"))
print("Wrote \(icns.path) and docs/icon.png")
