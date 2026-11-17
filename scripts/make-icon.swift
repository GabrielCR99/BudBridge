// Renders the app icon as vector art and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linearGradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// One earbud pointing its stem down-outward. `mirrored` draws the right bud.
func drawEarbud(_ ctx: CGContext, center: CGPoint, mirrored: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    if mirrored { ctx.scaleBy(x: -1, y: 1) }
    ctx.rotate(by: -0.32)

    // Stem
    let stem = CGPath(roundedRect: CGRect(x: -46, y: -300, width: 92, height: 290),
                      cornerWidth: 46, cornerHeight: 46, transform: nil)
    // Head
    let head = CGPath(ellipseIn: CGRect(x: -118, y: -100, width: 236, height: 220), transform: nil)

    let body = CGMutablePath()
    body.addPath(stem)
    body.addPath(head)

    // Soft drop shadow under the whole bud
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x000000, 0.45))
    ctx.addPath(body)
    ctx.setFillColor(color(0xF4F7FB))
    ctx.fillPath()
    ctx.restoreGState()

    // Glossy white-to-pearl shading
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    linearGradient(ctx, [color(0xFFFFFF), color(0xDCE3EE), color(0xB9C4D6)],
                   from: CGPoint(x: -120, y: 120), to: CGPoint(x: 110, y: -300))
    ctx.restoreGState()

    // Silicone ear tip
    let tip = CGPath(ellipseIn: CGRect(x: 52, y: -26, width: 104, height: 112), transform: nil)
    ctx.saveGState()
    ctx.addPath(tip)
    ctx.clip()
    linearGradient(ctx, [color(0x5B6B86), color(0x2A3347)],
                   from: CGPoint(x: 60, y: 86), to: CGPoint(x: 156, y: -26))
    ctx.restoreGState()

    // Specular highlight on the head
    let shine = CGPath(ellipseIn: CGRect(x: -86, y: 40, width: 74, height: 42), transform: nil)
    ctx.addPath(shine)
    ctx.setFillColor(color(0xFFFFFF, 0.85))
    ctx.fillPath()

    // Accent ring at the stem tip (mic)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -46, y: -300, width: 92, height: 40),
                       cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.setFillColor(color(0x4FD8F0))
    ctx.fillPath()

    ctx.restoreGState()
}

func renderIcon() -> CGImage {
    let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // macOS icon grid: 824 pt body centered on a 1024 canvas, continuous-corner squircle.
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: bodyRect, cornerWidth: 186, cornerHeight: 186, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x151C3D))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    linearGradient(ctx, [color(0x3B4FB8), color(0x1B2358), color(0x0B0F26)],
                   from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))

    // Glow behind the buds
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [color(0x4FD8F0, 0.38), color(0x4FD8F0, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])

    // Sound waves between the buds
    ctx.setLineCap(.round)
    for (i, radius) in [70.0, 130.0, 190.0].enumerated() {
        ctx.setStrokeColor(color(0x7FE6F7, 0.95 - Double(i) * 0.25))
        ctx.setLineWidth(26 - CGFloat(i) * 4)
        ctx.addArc(center: CGPoint(x: 512, y: 640), radius: radius,
                   startAngle: .pi * 0.30, endAngle: .pi * 0.70, clockwise: false)
        ctx.strokePath()
    }

    drawEarbud(ctx, center: CGPoint(x: 330, y: 560), mirrored: false)
    drawEarbud(ctx, center: CGPoint(x: 694, y: 560), mirrored: true)

    // Top sheen
    ctx.addPath(squircle)
    ctx.clip()
    linearGradient(ctx, [color(0xFFFFFF, 0.14), color(0xFFFFFF, 0)],
                   from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 640))
    ctx.restoreGState()

    // Hairline edge
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, size: Int, to url: URL) throws {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = renderIcon()
for base in [16, 32, 128, 256, 512] {
    try writePNG(master, size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(master, size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try writePNG(master, size: 1024, to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
