import CoreGraphics
import Foundation
import SketchCore

/// Vector export to SVG. Shapes are emitted as the same rough paths drawn on screen;
/// text uses <text> with the hand-drawn font embedded via @font-face when needed.
public enum SVGExporter {
    public static func svg(_ elements: [Element], files: [String: BinaryFile], options: ExportOptions) throws -> String {
        guard !elements.isEmpty else { throw ExportError.nothingToExport }
        let bounds = SceneExporter.exportBounds(elements, padding: options.padding)
        let theme = RenderTheme(isDark: options.darkMode)
        func color(_ c: RGBAColor) -> (String, Double) {
            let v = theme.isDark ? c.adaptedForDarkMode() : c
            return (v.withAlpha(1).hexString, v.a)
        }

        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
        version="1.1" width="\(fmt(bounds.width))" height="\(fmt(bounds.height))" \
        viewBox="\(fmt(bounds.minX)) \(fmt(bounds.minY)) \(fmt(bounds.width)) \(fmt(bounds.height))">

        """
        out += "<!-- Created with graphq -->\n"
        if elements.contains(where: { ($0.type == .text || $0.hasLabel) && $0.fontFamily == .hand }),
           let font = Fonts.handFontData {
            out += "<defs><style>@font-face { font-family: Virgil; src: url(data:font/woff2;base64,\(font.base64EncodedString())) format('woff2'); }</style></defs>\n"
        }
        if options.includeBackground {
            out += "<rect x=\"\(fmt(bounds.minX))\" y=\"\(fmt(bounds.minY))\" width=\"\(fmt(bounds.width))\" height=\"\(fmt(bounds.height))\" fill=\"\(theme.background.hexString)\"/>\n"
        }

        for e in elements {
            let c = e.center
            var transform = "translate(\(fmt(c.x)) \(fmt(c.y)))"
            if e.angle != 0 { transform += " rotate(\(fmt(e.angle * 180 / .pi)))" }
            transform += " translate(\(fmt(-e.width / 2)) \(fmt(-e.height / 2)))"
            let opacity = e.opacity < 0.999 ? " opacity=\"\(fmt(e.opacity))\"" : ""
            out += "<g transform=\"\(transform)\"\(opacity)>\n"

            switch e.type {
            case .image:
                if let id = e.fileId, let f = files[id] {
                    let href = "data:\(f.mimeType);base64,\(f.data.base64EncodedString())"
                    if let c = e.crop {
                        // Crop via a nested viewport over a unit-sized image.
                        out += "  <svg x=\"0\" y=\"0\" width=\"\(fmt(e.width))\" height=\"\(fmt(e.height))\" viewBox=\"\(fmt(c.minX)) \(fmt(c.minY)) \(fmt(c.width)) \(fmt(c.height))\" preserveAspectRatio=\"none\"><image x=\"0\" y=\"0\" width=\"1\" height=\"1\" preserveAspectRatio=\"none\" href=\"\(href)\"/></svg>\n"
                    } else {
                        out += "  <image x=\"0\" y=\"0\" width=\"\(fmt(e.width))\" height=\"\(fmt(e.height))\" preserveAspectRatio=\"none\" href=\"\(href)\"/>\n"
                    }
                }
            case .frame:
                let fill = e.fillColor.isTransparent ? "none" : color(e.fillColor).0
                out += "  <rect x=\"0\" y=\"0\" width=\"\(fmt(e.width))\" height=\"\(fmt(e.height))\" rx=\"6\" fill=\"\(fill)\" stroke=\"#8a8f98\" stroke-width=\"1.2\"/>\n"
                out += "  <text x=\"2\" y=\"-7\" font-family=\"\(Fonts.cssFamily(.normal))\" font-size=\"13\" fill=\"#6b7280\">\(escape(e.text.isEmpty ? "Frame" : e.text))</text>\n"
            case .text:
                out += textSVG(e, box: CGRect(x: 0, y: 0, width: e.width, height: e.height), wrap: false, color: color(e.strokeColor))
            default:
                for item in ShapeBuilder.build(e) {
                    let (hex, alpha) = color(item.role == .stroke ? e.strokeColor : e.fillColor)
                    let d = pathData(item.ops)
                    switch item.kind {
                    case .fill:
                        out += "  <path d=\"\(d)\" fill=\"\(hex)\"\(alpha < 1 ? " fill-opacity=\"\(fmt(alpha))\"" : "") stroke=\"none\"/>\n"
                    case .stroke(let width, let dash):
                        let dashAttr = dash.map { " stroke-dasharray=\"\($0.map(fmt).joined(separator: " "))\"" } ?? ""
                        out += "  <path d=\"\(d)\" fill=\"none\" stroke=\"\(hex)\"\(alpha < 1 ? " stroke-opacity=\"\(fmt(alpha))\"" : "") stroke-width=\"\(fmt(width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(dashAttr)/>\n"
                    }
                }
                if e.hasLabel {
                    out += textSVG(e, box: TextMetrics.labelBox(for: e), wrap: true, color: color(e.strokeColor))
                }
                if e.hasLinearLabel {
                    let size = TextLayout(text: e.text, family: e.fontFamily, fontSize: e.fontSize).size
                    var box = TextMetrics.linearLabelRect(for: e, size: size)
                    let knock = box.insetBy(dx: -4, dy: -2)
                    out += "  <rect x=\"\(fmt(knock.minX))\" y=\"\(fmt(knock.minY))\" width=\"\(fmt(knock.width))\" height=\"\(fmt(knock.height))\" fill=\"\(theme.background.hexString)\"/>\n"
                    var centered = e
                    centered.textAlign = .center
                    box.size.height = size.height
                    out += textSVG(centered, box: box, wrap: false, color: color(e.strokeColor))
                }
            }
            out += "</g>\n"
        }
        out += "</svg>\n"
        return out
    }

    static func textSVG(_ e: Element, box: CGRect, wrap: Bool, color: (String, Double)) -> String {
        let layout = TextLayout(text: e.text, family: e.fontFamily, fontSize: e.fontSize, maxWidth: wrap ? box.width : nil)
        let top = wrap ? box.midY - layout.size.height / 2 : box.minY
        let (x, anchor): (CGFloat, String) = switch e.textAlign {
        case .left: (box.minX, "start")
        case .center: (box.midX, "middle")
        case .right: (box.maxX, "end")
        }
        var s = ""
        for (i, line) in layout.lines.enumerated() where !line.string.isEmpty {
            let y = top + CGFloat(i) * layout.lineHeight + layout.baselineOffset
            s += "  <text x=\"\(fmt(x))\" y=\"\(fmt(y))\" font-family=\"\(Fonts.cssFamily(e.fontFamily))\" font-size=\"\(fmt(e.fontSize))\" fill=\"\(color.0)\"\(color.1 < 1 ? " fill-opacity=\"\(fmt(color.1))\"" : "") text-anchor=\"\(anchor)\" style=\"white-space: pre\">\(escape(line.string))</text>\n"
        }
        return s
    }

    public static func pathData(_ ops: [PathOp]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(ops.count)
        for op in ops {
            switch op {
            case .move(let p): parts.append("M\(fmt(p.x)) \(fmt(p.y))")
            case .line(let p): parts.append("L\(fmt(p.x)) \(fmt(p.y))")
            case .curve(let a, let b, let p):
                parts.append("C\(fmt(a.x)) \(fmt(a.y)) \(fmt(b.x)) \(fmt(b.y)) \(fmt(p.x)) \(fmt(p.y))")
            }
        }
        return parts.joined(separator: " ")
    }

    static func fmt(_ v: CGFloat) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%.2f", Double(r))
    }

    static func fmt(_ v: Double) -> String { fmt(CGFloat(v)) }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
