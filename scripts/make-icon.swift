import AppKit
import CoreGraphics

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(in context: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let body = canvas.insetBy(dx: 100, dy: 100)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(bodyPath)
    context.setFillColor(color(0x4338CA))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x6366F1), color(0x4F46E5), color(0x7C3AED)] as CFArray,
        locations: [0, 0.5, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    let shine = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(shine, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: 560), options: [])
    context.restoreGState()

    let card = CGRect(x: 262, y: 236, width: 500, height: 552)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 70, cornerHeight: 70, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x1E1B4B, 0.45))
    context.addPath(cardPath)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    let rows: [(y: CGFloat, done: Bool, barWidth: CGFloat)] = [
        (650, true, 250),
        (512, false, 270),
        (374, false, 190)
    ]
    for row in rows {
        let circle = CGRect(x: 318, y: row.y - 38, width: 76, height: 76)
        if row.done {
            context.setFillColor(color(0x22C55E))
            context.fillEllipse(in: circle)
            context.setStrokeColor(color(0xFFFFFF))
            context.setLineWidth(13)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: circle.minX + 20, y: circle.midY + 1))
            context.addLine(to: CGPoint(x: circle.minX + 33, y: circle.midY - 13))
            context.addLine(to: CGPoint(x: circle.maxX - 18, y: circle.midY + 15))
            context.strokePath()
        } else {
            context.setStrokeColor(color(0x6366F1))
            context.setLineWidth(12)
            context.strokeEllipse(in: circle.insetBy(dx: 6, dy: 6))
        }
        let bar = CGRect(x: 424, y: row.y - 15, width: row.barWidth, height: 30)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 15, cornerHeight: 15, transform: nil))
        context.setFillColor(row.done ? color(0xCBD5E1) : color(0x334155))
        context.fillPath()
    }

    let badgeCenter = CGPoint(x: 742, y: 760)
    let badgeRadius: CGFloat = 112
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x7C2D12, 0.45))
    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: badgeCenter.x - badgeRadius - 12, y: badgeCenter.y - badgeRadius - 12, width: (badgeRadius + 12) * 2, height: (badgeRadius + 12) * 2))
    context.restoreGState()

    context.saveGState()
    let badgeRect = CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius, width: badgeRadius * 2, height: badgeRadius * 2)
    context.addEllipse(in: badgeRect)
    context.clip()
    let badgeGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFBBF24), color(0xF97316)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(badgeGradient, start: CGPoint(x: badgeRect.minX, y: badgeRect.maxY), end: CGPoint(x: badgeRect.maxX, y: badgeRect.minY), options: [])
    context.restoreGState()

    context.setStrokeColor(color(0xFFFFFF))
    context.setLineCap(.round)
    context.setLineWidth(20)
    context.move(to: badgeCenter)
    context.addLine(to: CGPoint(x: badgeCenter.x, y: badgeCenter.y + 62))
    context.strokePath()
    context.move(to: badgeCenter)
    context.addLine(to: CGPoint(x: badgeCenter.x + 46, y: badgeCenter.y - 24))
    context.strokePath()
    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: badgeCenter.x - 16, y: badgeCenter.y - 16, width: 32, height: 32))
}

func render(pixels: Int) throws -> Data {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    let image = context.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage: image)
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for size in sizes {
    let suffix = size.scale == 1 ? "" : "@2x"
    let name = "icon_\(size.points)x\(size.points)\(suffix).png"
    try render(pixels: size.points * size.scale).write(to: outputDirectory.appendingPathComponent(name))
}
try render(pixels: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
print("Wrote \(sizes.count) sizes to \(outputDirectory.path)")
