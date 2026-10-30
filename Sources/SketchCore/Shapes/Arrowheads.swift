import CoreGraphics
import Foundation

public enum Arrowheads {
    static func baseSize(_ head: Arrowhead, strokeWidth: Double) -> Double {
        let w = strokeWidth
        switch head {
        case .none: return 0
        case .arrow: return 16 + w * 3
        case .triangle: return 12 + w * 3
        case .diamond: return 14 + w * 3
        case .dot: return 8 + w * 2
        case .bar: return 10 + w * 3
        }
    }

    /// Tip point and unit direction (pointing outward) for one end of a linear element.
    public static func endFrame(_ e: Element, end: LinearEnd) -> (tip: CGPoint, dir: CGPoint, segment: Double)? {
        let path = e.localPath
        guard path.count >= 2 else { return nil }
        let pts = end == .end ? path : path.reversed()
        let tip = pts[pts.count - 1]
        // Walk back along the (possibly flattened) path to get a stable direction on curves.
        var j = pts.count - 2
        while j > 0 && pts[j].distance(to: tip) < 8 { j -= 1 }
        let dir = (tip - pts[j]).normalized
        let raw = end == .end ? e.points : e.points.reversed()
        let segment = raw[raw.count - 1].distance(to: raw[raw.count - 2])
        return (tip, dir, Double(segment))
    }

    static func items(for e: Element, options base: RoughOptions) -> [DrawItem] {
        var items: [DrawItem] = []
        for (end, head) in [(LinearEnd.start, e.startArrowhead), (LinearEnd.end, e.endArrowhead)] where head != .none {
            guard let frame = endFrame(e, end: end) else { continue }
            var o = base
            o.seed = e.seed + (end == .start ? 11 : 17)
            o.disableMultiStroke = false
            o.preserveVertices = true
            items += makeHead(head, tip: frame.tip, dir: frame.dir,
                          size: min(baseSize(head, strokeWidth: e.strokeWidth), max(frame.segment * 0.45, 4)),
                          options: o, strokeWidth: e.strokeWidth)
        }
        return items
    }

    static func makeHead(_ kind: Arrowhead, tip: CGPoint, dir: CGPoint, size: Double,
                     options o: RoughOptions, strokeWidth: Double) -> [DrawItem] {
        let gen = RoughGenerator(options: o)
        let perp = dir.perpendicular
        let stroke = DrawItem.Kind.stroke(width: o.strokeWidth, dash: nil)
        switch kind {
        case .none:
            return []
        case .arrow:
            let angle = 25.0 * .pi / 180
            let back = tip - dir * size
            let w1 = back.rotated(around: tip, by: angle)
            let w2 = back.rotated(around: tip, by: -angle)
            return [DrawItem(kind: stroke, role: .stroke, ops: gen.line(w1, tip) + gen.line(w2, tip))]
        case .triangle:
            let back = tip - dir * size
            let poly = [tip, back + perp * (size * 0.5), back - perp * (size * 0.5)]
            return [DrawItem(kind: .fill, role: .stroke, ops: polygonOps(poly)),
                    DrawItem(kind: stroke, role: .stroke, ops: gen.polygon(poly))]
        case .diamond:
            let mid = tip - dir * (size / 2)
            let poly = [tip, mid + perp * (size * 0.3), tip - dir * size, mid - perp * (size * 0.3)]
            return [DrawItem(kind: .fill, role: .stroke, ops: polygonOps(poly)),
                    DrawItem(kind: stroke, role: .stroke, ops: gen.polygon(poly))]
        case .dot:
            let c = tip - dir * (size / 2)
            let ellipse = gen.ellipse(center: c, width: size, height: size)
            return [DrawItem(kind: .fill, role: .stroke, ops: polygonOps(Curves.ellipsePoints(
                        in: CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size), steps: 24))),
                    DrawItem(kind: stroke, role: .stroke, ops: ellipse.stroke.ops)]
        case .bar:
            return [DrawItem(kind: stroke, role: .stroke, ops: gen.line(tip + perp * (size / 2), tip - perp * (size / 2)))]
        }
    }

    private static func polygonOps(_ poly: [CGPoint]) -> [PathOp] {
        guard let f = poly.first else { return [] }
        return [.move(f)] + poly.dropFirst().map { .line($0) }
    }
}
