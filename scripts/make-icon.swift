// scripts/make-icon.swift — render the Kokoro Studio app icon.
// "Kokoro" means "heart" in Japanese: a heart with a heartbeat waveform.
//
// Usage: swift scripts/make-icon.swift assets
// Writes assets/AppIcon.iconset/*.png; convert with:
//   iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns

import AppKit

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
let iconsetPath = "\(outputDirectory)/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconsetPath,
                                        withIntermediateDirectories: true)

let canvas: CGFloat = 1024

func drawIcon(into context: CGContext) {
    // macOS-style rounded square with a margin, vertical sunset gradient.
    let inset: CGFloat = 100
    let plate = CGRect(x: inset, y: inset,
                       width: canvas - 2 * inset, height: canvas - 2 * inset)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185,
                           transform: nil)
    context.addPath(platePath)
    context.clip()

    let colors = [
        NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.45, alpha: 1).cgColor, // coral
        NSColor(calibratedRed: 0.82, green: 0.19, blue: 0.42, alpha: 1).cgColor, // raspberry
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: canvas / 2, y: canvas - inset),
                               end: CGPoint(x: canvas / 2, y: inset),
                               options: [])

    // Heart = diamond + two circles (classic construction), in white.
    let cx = canvas / 2
    let heartCenterY = canvas / 2 - 10
    let diagonal: CGFloat = 430
    let radius = diagonal * CGFloat(2).squareRoot() / 4 // half the square side
    let tip = CGPoint(x: cx, y: heartCenterY - diagonal * 0.52)

    // Wind the diamond the same direction as addEllipse so the winding-rule
    // fill produces the union (opposite windings cancel where they overlap).
    let heart = CGMutablePath()
    heart.move(to: tip)
    heart.addLine(to: CGPoint(x: cx + diagonal / 2, y: tip.y + diagonal / 2))
    heart.addLine(to: CGPoint(x: cx, y: tip.y + diagonal))
    heart.addLine(to: CGPoint(x: cx - diagonal / 2, y: tip.y + diagonal / 2))
    heart.closeSubpath()
    heart.addEllipse(in: CGRect(x: cx - diagonal / 2 - radius + diagonal / 4,
                                y: tip.y + diagonal * 0.75 - radius,
                                width: radius * 2, height: radius * 2))
    heart.addEllipse(in: CGRect(x: cx + diagonal / 4 - radius,
                                y: tip.y + diagonal * 0.75 - radius,
                                width: radius * 2, height: radius * 2))

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.addPath(heart)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    // Heartbeat / waveform line across the heart, clipped inside it.
    context.saveGState()
    context.addPath(heart)
    context.clip()

    let beatY = heartCenterY + 30
    let beat = CGMutablePath()
    beat.move(to: CGPoint(x: cx - 320, y: beatY))
    beat.addLine(to: CGPoint(x: cx - 130, y: beatY))
    beat.addLine(to: CGPoint(x: cx - 90, y: beatY + 50))
    beat.addLine(to: CGPoint(x: cx - 35, y: beatY - 175))
    beat.addLine(to: CGPoint(x: cx + 30, y: beatY + 195))
    beat.addLine(to: CGPoint(x: cx + 80, y: beatY - 40))
    beat.addLine(to: CGPoint(x: cx + 115, y: beatY))
    beat.addLine(to: CGPoint(x: cx + 320, y: beatY))

    context.addPath(beat)
    context.setStrokeColor(NSColor(calibratedRed: 0.82, green: 0.19, blue: 0.42,
                                   alpha: 1).cgColor)
    context.setLineWidth(34)
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.strokePath()
    context.restoreGState()

    // A couple of whimsical sparkles.
    func sparkle(at center: CGPoint, size: CGFloat) {
        let s = CGMutablePath()
        s.move(to: CGPoint(x: center.x, y: center.y + size))
        s.addQuadCurve(to: CGPoint(x: center.x + size, y: center.y),
                       control: CGPoint(x: center.x + size * 0.18, y: center.y + size * 0.18))
        s.addQuadCurve(to: CGPoint(x: center.x, y: center.y - size),
                       control: CGPoint(x: center.x + size * 0.18, y: center.y - size * 0.18))
        s.addQuadCurve(to: CGPoint(x: center.x - size, y: center.y),
                       control: CGPoint(x: center.x - size * 0.18, y: center.y - size * 0.18))
        s.addQuadCurve(to: CGPoint(x: center.x, y: center.y + size),
                       control: CGPoint(x: center.x - size * 0.18, y: center.y + size * 0.18))
        s.closeSubpath()
        context.addPath(s)
        context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.fillPath()
    }
    sparkle(at: CGPoint(x: cx + 255, y: heartCenterY + 250), size: 52)
    sparkle(at: CGPoint(x: cx - 285, y: heartCenterY - 210), size: 34)
}

func renderPNG(pixels: Int, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
                               pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0,
                               bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(into: cg)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

for size in [16, 32, 128, 256, 512] {
    renderPNG(pixels: size, to: "\(iconsetPath)/icon_\(size)x\(size).png")
    renderPNG(pixels: size * 2, to: "\(iconsetPath)/icon_\(size)x\(size)@2x.png")
}
print("Wrote \(iconsetPath)")
