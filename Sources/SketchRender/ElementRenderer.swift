import CoreGraphics
import Foundation
import ImageIO
import SketchCore

public struct RenderTheme: Hashable, Sendable {
    public var isDark: Bool

    public init(isDark: Bool) { self.isDark = isDark }

    public static let light = RenderTheme(isDark: false)
    public static let dark = RenderTheme(isDark: true)

    public var background: RGBAColor {
        isDark ? RGBAColor(hex: "#18181b")! : RGBAColor(hex: "#ffffff")!
    }
}

public extension PathOp {
    static func cgPath(_ ops: [PathOp]) -> CGPath {
        let path = CGMutablePath()
        for op in ops {
            switch op {
            case .move(let p): path.move(to: p)
            case .line(let p): path.addLine(to: p)
            case .curve(let c1, let c2, let p): path.addCurve(to: p, control1: c1, control2: c2)
            }
        }
        return path
    }
}

/// Draws elements into a y-down CGContext. Rough geometry is generated once per
/// element version and cached as CGPaths, so redraws only replay paths.
public final class ElementRenderer {
    private struct CachedItem {
        let path: CGPath
        let kind: DrawItem.Kind
        let role: ColorRole
    }

    private struct CachedShape {
        let nonce: Int
        let items: [CachedItem]
    }

    private var shapes: [String: CachedShape] = [:]
    private var images: [String: CGImage] = [:]
    private var colors: [RGBAColor: CGColor] = [:]
    public let textCache = TextLayoutCache()
    public var theme: RenderTheme = .light {
        didSet { if theme != oldValue { colors.removeAll() } }
    }

    public init(theme: RenderTheme = .light) {
        self.theme = theme
        Fonts.registerBundledFonts()
    }

    // MARK: Caches

    public func purge(keeping ids: Set<String>) {
        shapes = shapes.filter { ids.contains($0.key) }
    }

    public func removeAll() {
        shapes.removeAll()
        images.removeAll()
    }

    public func cgColor(_ c: RGBAColor) -> CGColor {
        if let cached = colors[c] { return cached }
        let v = theme.isDark ? c.adaptedForDarkMode() : c
        let cg = CGColor(srgbRed: v.r, green: v.g, blue: v.b, alpha: v.a)
        colors[c] = cg
        return cg
    }

    private func items(for e: Element) -> [CachedItem] {
        if let c = shapes[e.id], c.nonce == e.versionNonce { return c.items }
        let built = ShapeBuilder.build(e).map {
            CachedItem(path: PathOp.cgPath($0.ops), kind: $0.kind, role: $0.role)
        }
        shapes[e.id] = CachedShape(nonce: e.versionNonce, items: built)
        return built
    }

    public func image(for fileId: String, files: [String: BinaryFile]) -> CGImage? {
        if let img = images[fileId] { return img }
        guard let file = files[fileId],
              let src = CGImageSourceCreateWithData(file.data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else { return nil }
        images[fileId] = img
        return img
    }

    // MARK: Drawing

    /// Draws a single element. The context must be y-down in scene coordinates.
    public func draw(_ e: Element, in ctx: CGContext, files: [String: BinaryFile], hideText: Bool = false) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let c = e.center
        ctx.translateBy(x: c.x, y: c.y)
        if e.angle != 0 { ctx.rotate(by: e.angle) }
        ctx.translateBy(x: -e.width / 2, y: -e.height / 2)

        let translucent = e.opacity < 0.999
        if translucent {
            ctx.setAlpha(max(0, e.opacity))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer { if translucent { ctx.endTransparencyLayer() } }

        switch e.type {
        case .text:
            if !hideText { drawText(e, in: ctx, box: CGRect(x: 0, y: 0, width: e.width, height: e.height), wrap: false) }
        case .image:
            drawImage(e, in: ctx, files: files)
        default:
            drawItems(items(for: e), in: ctx, element: e)
            if e.hasLabel && !hideText {
                drawText(e, in: ctx, box: TextMetrics.labelBox(for: e), wrap: true)
            }
        }
    }

    private func drawItems(_ items: [CachedItem], in ctx: CGContext, element e: Element) {
        let stroke = cgColor(e.strokeColor)
        let fill = cgColor(e.fillColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for item in items {
            let color = item.role == .stroke ? stroke : fill
            ctx.addPath(item.path)
            switch item.kind {
            case .fill:
                ctx.setFillColor(color)
                ctx.fillPath()
            case .stroke(let width, let dash):
                ctx.setStrokeColor(color)
                ctx.setLineWidth(width)
                if let dash { ctx.setLineDash(phase: 0, lengths: dash.map { CGFloat($0) }) } else { ctx.setLineDash(phase: 0, lengths: []) }
                ctx.strokePath()
            }
        }
    }

    private func drawText(_ e: Element, in ctx: CGContext, box: CGRect, wrap: Bool) {
        guard !e.text.isEmpty else { return }
        let layout = textCache.layout(text: e.text, family: e.fontFamily, fontSize: e.fontSize,
                                      maxWidth: wrap ? box.width : nil)
        var rect = box
        if wrap {
            // Vertically center the label in its container.
            rect.origin.y = box.midY - layout.size.height / 2
            rect.size.height = layout.size.height
        }
        layout.draw(in: ctx, rect: rect, align: e.textAlign, color: cgColor(e.strokeColor))
    }

    private func drawImage(_ e: Element, in ctx: CGContext, files: [String: BinaryFile]) {
        let rect = CGRect(x: 0, y: 0, width: e.width, height: e.height)
        guard let id = e.fileId, let img = image(for: id, files: files) else {
            // Placeholder while the file is missing.
            ctx.setFillColor(cgColor(RGBAColor(hex: "#e9ecef")!))
            ctx.fill(rect)
            return
        }
        ctx.saveGState()
        if e.roundness > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: min(e.effectiveRadius, rect.width / 2),
                               cornerHeight: min(e.effectiveRadius, rect.height / 2), transform: nil))
            ctx.clip()
        }
        // CGImage draws bottom-up; flip locally for the y-down scene space.
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    /// Draws a list of elements back-to-front.
    public func draw(_ elements: [Element], in ctx: CGContext, files: [String: BinaryFile]) {
        for e in elements { draw(e, in: ctx, files: files) }
    }
}
