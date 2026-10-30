import CoreGraphics
import CoreText
import Foundation
import SketchCore

/// Laid-out text: one CTLine per visual line. Line height follows Excalidraw (1.25 × font size).
public final class TextLayout {
    public struct Line {
        public let ctLine: CTLine
        public let string: String
        public let width: CGFloat
    }

    public let lines: [Line]
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    public let size: CGSize

    public static let lineHeightFactor: CGFloat = 1.25

    public init(text: String, family: FontFamily, fontSize: CGFloat, maxWidth: CGFloat? = nil) {
        let font = Fonts.ctFont(family, size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        var lines: [Line] = []
        let paragraphs = text.components(separatedBy: "\n")
        for para in paragraphs {
            let attributed = NSAttributedString(string: para, attributes: attrs)
            guard let maxWidth, maxWidth > 0, !para.isEmpty else {
                let line = CTLineCreateWithAttributedString(attributed)
                lines.append(Line(ctLine: line, string: para, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))))
                continue
            }
            // Word-wrap the paragraph to maxWidth.
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let length = attributed.length
            var start = 0
            while start < length {
                var count = CTTypesetterSuggestLineBreak(typesetter, start, Double(maxWidth))
                if count <= 0 { count = 1 }
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                let sub = (para as NSString).substring(with: NSRange(location: start, length: count))
                let trimmedWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
                lines.append(Line(ctLine: line, string: sub.trimmingCharacters(in: .whitespaces), width: trimmedWidth))
                start += count
            }
        }
        self.lines = lines
        self.fontSize = fontSize
        self.lineHeight = fontSize * Self.lineHeightFactor
        self.ascent = CTFontGetAscent(font)
        self.descent = CTFontGetDescent(font)
        let width = lines.map(\.width).max() ?? 0
        self.size = CGSize(width: ceil(width), height: ceil(CGFloat(max(lines.count, 1)) * lineHeight))
    }

    /// Draws the lines into `rect` (y-down context) with the given alignment.
    public func draw(in ctx: CGContext, rect: CGRect, align: TextAlign, color: CGColor) {
        ctx.saveGState()
        ctx.setFillColor(color)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (i, line) in lines.enumerated() {
            let x: CGFloat
            switch align {
            case .left: x = rect.minX
            case .center: x = rect.minX + (rect.width - line.width) / 2
            case .right: x = rect.maxX - line.width
            }
            let baseline = rect.minY + CGFloat(i) * lineHeight + baselineOffset
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line.ctLine, ctx)
        }
        ctx.restoreGState()
    }

    /// Distance from the top of a line box to its baseline (glyph box centered in the line).
    public var baselineOffset: CGFloat { (lineHeight - (ascent + descent)) / 2 + ascent }
}

/// Small LRU-less cache; layouts are cheap but CTLine creation per frame is not.
public final class TextLayoutCache {
    private struct Key: Hashable {
        var text: String
        var family: FontFamily
        var size: CGFloat
        var maxWidth: CGFloat?
    }

    private var store: [Key: TextLayout] = [:]

    public init() {}

    public func layout(text: String, family: FontFamily, fontSize: CGFloat, maxWidth: CGFloat? = nil) -> TextLayout {
        let key = Key(text: text, family: family, size: fontSize, maxWidth: maxWidth.map { $0.rounded() })
        if let l = store[key] { return l }
        if store.count > 2000 { store.removeAll(keepingCapacity: true) }
        let l = TextLayout(text: text, family: family, fontSize: fontSize, maxWidth: maxWidth.map { $0.rounded() })
        store[key] = l
        return l
    }
}

public enum TextMetrics {
    /// Inner padding between a container's outline and its label.
    public static let labelPadding: CGFloat = 8

    /// Natural size of standalone text.
    public static func measure(_ text: String, family: FontFamily, fontSize: CGFloat) -> CGSize {
        let l = TextLayout(text: text.isEmpty ? " " : text, family: family, fontSize: fontSize)
        return CGSize(width: max(l.size.width, 1), height: l.size.height)
    }

    /// The box inside a container in which its label is laid out (element-local coordinates).
    public static func labelBox(for e: Element) -> CGRect {
        let p = labelPadding
        switch e.type {
        case .ellipse:
            // Largest axis-aligned rect inside the ellipse.
            let w = e.width / 2.0.squareRoot(), h = e.height / 2.0.squareRoot()
            return CGRect(x: (e.width - w) / 2 + p / 2, y: (e.height - h) / 2, width: max(w - p, 1), height: h)
        case .diamond:
            let w = e.width / 2, h = e.height / 2
            return CGRect(x: (e.width - w) / 2 + p / 2, y: (e.height - h) / 2, width: max(w - p, 1), height: h)
        default:
            return CGRect(x: p, y: p, width: max(e.width - p * 2, 1), height: max(e.height - p * 2, 1))
        }
    }

    /// Box of an arrow/line label of the given size, centered on the path midpoint (local).
    public static func linearLabelRect(for e: Element, size: CGSize) -> CGRect {
        let a = e.labelAnchor
        return CGRect(x: a.x - size.width / 2, y: a.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Minimum container height so that its label fits.
    public static func requiredContainerHeight(for e: Element) -> CGFloat {
        let box = labelBox(for: e)
        let h = TextLayout(text: e.text, family: e.fontFamily, fontSize: e.fontSize, maxWidth: box.width).size.height
        switch e.type {
        case .ellipse: return h * 2.0.squareRoot() + labelPadding
        case .diamond: return h * 2 + labelPadding
        default: return h + labelPadding * 2
        }
    }
}
