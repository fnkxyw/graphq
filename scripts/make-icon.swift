// Renders the graphq app icon into an .iconset directory.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: content inset ~10%, continuous-corner squircle.
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor(srgbRed: 0.99, green: 0.98, blue: 0.96, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // Dot grid.
    ctx.setFillColor(NSColor.black.withAlphaComponent(0.08).cgColor)
    let step = rect.width / 9
    for i in 1..<9 { for j in 1..<9 {
        let d = s * 0.008
        ctx.fillEllipse(in: CGRect(x: rect.minX + CGFloat(i) * step - d, y: rect.minY + CGFloat(j) * step - d, width: d * 2, height: d * 2))
    } }

    // Sketchy rectangle with blue hachure, then an arrow — drawn twice for the hand-drawn look.
    let box = CGRect(x: rect.minX + rect.width * 0.17, y: rect.minY + rect.height * 0.42,
                     width: rect.width * 0.42, height: rect.height * 0.3)
    ctx.saveGState()
    ctx.addRect(box)
    ctx.clip()
    ctx.setStrokeColor(NSColor(srgbRed: 0.25, green: 0.45, blue: 0.88, alpha: 0.55).cgColor)
    ctx.setLineWidth(s * 0.012)
    var x = box.minX - box.height
    while x < box.maxX {
        ctx.move(to: CGPoint(x: x, y: box.minY)); ctx.addLine(to: CGPoint(x: x + box.height, y: box.maxY))
        x += s * 0.035
    }
    ctx.strokePath()
    ctx.restoreGState()

    let ink = NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1).cgColor
    ctx.setStrokeColor(ink)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(s * 0.022)
    for (j, k) in [(0.0, 0.0), (0.006, -0.005)] {
        let o = CGPoint(x: s * j, y: s * k)
        ctx.move(to: CGPoint(x: box.minX + o.x, y: box.minY - o.y))
        ctx.addCurve(to: CGPoint(x: box.maxX + o.y, y: box.minY + o.x),
                     control1: CGPoint(x: box.minX + box.width * 0.3, y: box.minY + s * 0.006),
                     control2: CGPoint(x: box.minX + box.width * 0.7, y: box.minY - s * 0.004))
        ctx.addLine(to: CGPoint(x: box.maxX - o.x, y: box.maxY + o.y))
        ctx.addCurve(to: CGPoint(x: box.minX - o.y, y: box.maxY - o.x),
                     control1: CGPoint(x: box.minX + box.width * 0.6, y: box.maxY + s * 0.005),
                     control2: CGPoint(x: box.minX + box.width * 0.3, y: box.maxY - s * 0.003))
        ctx.closePath()
    }
    ctx.strokePath()

    // Arrow from the box up to the right.
    let start = CGPoint(x: box.maxX + s * 0.03, y: box.maxY - s * 0.02)
    let end = CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.maxY - rect.height * 0.16)
    ctx.move(to: start)
    ctx.addCurve(to: end, control1: CGPoint(x: start.x + s * 0.12, y: start.y + s * 0.02),
                 control2: CGPoint(x: end.x - s * 0.02, y: end.y - s * 0.14))
    let a1 = CGPoint(x: end.x - s * 0.075, y: end.y - s * 0.02)
    let a2 = CGPoint(x: end.x + s * 0.01, y: end.y - s * 0.08)
    ctx.move(to: a1); ctx.addLine(to: end); ctx.addLine(to: a2)
    ctx.strokePath()

    // Pencil scribble at the bottom.
    ctx.setStrokeColor(NSColor(srgbRed: 0.84, green: 0.35, blue: 0.35, alpha: 1).cgColor)
    ctx.setLineWidth(s * 0.02)
    let y0 = rect.minY + rect.height * 0.2
    ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.17, y: y0))
    for i in 1...6 {
        let px = rect.minX + rect.width * (0.17 + 0.1 * CGFloat(i))
        ctx.addQuadCurve(to: CGPoint(x: px, y: y0), control: CGPoint(x: px - rect.width * 0.05, y: y0 + (i % 2 == 0 ? -1 : 1) * s * 0.05))
    }
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
