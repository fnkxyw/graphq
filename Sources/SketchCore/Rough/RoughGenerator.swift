import CoreGraphics
import Foundation

/// Port of the core of rough.js (https://github.com/rough-stuff/rough, MIT).
/// Produces renderer-agnostic `PathOp`s; all randomness comes from the seeded LCG,
/// so the same options always yield the same strokes.
public final class RoughGenerator {
    public let o: RoughOptions
    private var rng: RoughRandom

    public init(options: RoughOptions) {
        self.o = options
        self.rng = RoughRandom(seed: options.seed)
    }

    // MARK: Randomness helpers (names follow rough.js)

    private func random() -> Double { rng.next() }

    private func offset(_ minV: Double, _ maxV: Double, gain: Double = 1) -> Double {
        o.roughness * gain * (random() * (maxV - minV) + minV)
    }

    private func offsetOpt(_ x: Double, gain: Double = 1) -> Double { offset(-x, x, gain: gain) }

    /// Fresh generator with seed + 1, used for the second pass of multi-stroke curves.
    private func alteredSeed() -> RoughGenerator {
        var no = o
        no.seed = o.seed + 1
        return RoughGenerator(options: no)
    }

    // MARK: Lines

    private func singleLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                            move: Bool, overlay: Bool) -> [PathOp] {
        let lengthSq = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)
        let length = lengthSq.squareRoot()
        let gain: Double
        if length < 200 { gain = 1 } else if length > 500 { gain = 0.4 } else { gain = -0.0016668 * length + 1.233334 }

        var off = o.maxRandomnessOffset
        if off * off * 100 > lengthSq { off = length / 10 }
        let halfOffset = off / 2
        let divergePoint = 0.2 + random() * 0.2
        var midDispX = o.bowing * o.maxRandomnessOffset * (y2 - y1) / 200
        var midDispY = o.bowing * o.maxRandomnessOffset * (x1 - x2) / 200
        midDispX = offsetOpt(midDispX, gain: gain)
        midDispY = offsetOpt(midDispY, gain: gain)
        let randomHalf = { self.offsetOpt(halfOffset, gain: gain) }
        let randomFull = { self.offsetOpt(off, gain: gain) }
        let pv = o.preserveVertices

        var ops: [PathOp] = []
        if move {
            if overlay {
                ops.append(.move(CGPoint(x: x1 + (pv ? 0 : randomHalf()), y: y1 + (pv ? 0 : randomHalf()))))
            } else {
                ops.append(.move(CGPoint(x: x1 + (pv ? 0 : offsetOpt(off, gain: gain)),
                                         y: y1 + (pv ? 0 : offsetOpt(off, gain: gain)))))
            }
        }
        let r = overlay ? randomHalf : randomFull
        let c1 = CGPoint(x: midDispX + x1 + (x2 - x1) * divergePoint + r(),
                         y: midDispY + y1 + (y2 - y1) * divergePoint + r())
        let c2 = CGPoint(x: midDispX + x1 + 2 * (x2 - x1) * divergePoint + r(),
                         y: midDispY + y1 + 2 * (y2 - y1) * divergePoint + r())
        let end = CGPoint(x: x2 + (pv ? 0 : r()), y: y2 + (pv ? 0 : r()))
        ops.append(.curve(c1, c2, end))
        return ops
    }

    private func doubleLine(_ a: CGPoint, _ b: CGPoint, filling: Bool = false) -> [PathOp] {
        let single = filling ? o.disableMultiStrokeFill : o.disableMultiStroke
        let o1 = singleLine(a.x, a.y, b.x, b.y, move: true, overlay: false)
        if single { return o1 }
        return o1 + singleLine(a.x, a.y, b.x, b.y, move: true, overlay: true)
    }

    public func line(_ a: CGPoint, _ b: CGPoint) -> [PathOp] { doubleLine(a, b) }

    public func linearPath(_ points: [CGPoint], close: Bool) -> [PathOp] {
        guard points.count >= 2 else { return [] }
        if points.count == 2 { return doubleLine(points[0], points[1]) }
        var ops: [PathOp] = []
        for i in 0..<(points.count - 1) { ops += doubleLine(points[i], points[i + 1]) }
        if close { ops += doubleLine(points[points.count - 1], points[0]) }
        return ops
    }

    public func polygon(_ points: [CGPoint]) -> [PathOp] { linearPath(points, close: true) }

    public func rectangle(_ r: CGRect) -> [PathOp] { polygon(r.corners) }

    // MARK: Curves

    private func curveOps(_ points: [CGPoint], closePoint: CGPoint? = nil) -> [PathOp] {
        let len = points.count
        var ops: [PathOp] = []
        if len > 3 {
            let s = 1 - o.curveTightness
            ops.append(.move(points[1]))
            var i = 1
            while i + 2 < len {
                let p = points[i]
                let b1 = CGPoint(x: p.x + (s * points[i + 1].x - s * points[i - 1].x) / 6,
                                 y: p.y + (s * points[i + 1].y - s * points[i - 1].y) / 6)
                let b2 = CGPoint(x: points[i + 1].x + (s * points[i].x - s * points[i + 2].x) / 6,
                                 y: points[i + 1].y + (s * points[i].y - s * points[i + 2].y) / 6)
                ops.append(.curve(b1, b2, points[i + 1]))
                i += 1
            }
            if let cp = closePoint {
                let ro = o.maxRandomnessOffset
                ops.append(.line(CGPoint(x: cp.x + offsetOpt(ro), y: cp.y + offsetOpt(ro))))
            }
        } else if len == 3 {
            ops.append(.move(points[1]))
            ops.append(.curve(points[1], points[2], points[2]))
        } else if len == 2 {
            ops += doubleLine(points[0], points[1])
        }
        return ops
    }

    private func curveWithOffset(_ points: [CGPoint], offset off: Double) -> [PathOp] {
        guard let first = points.first else { return [] }
        var ps: [CGPoint] = []
        ps.append(CGPoint(x: first.x + offsetOpt(off), y: first.y + offsetOpt(off)))
        ps.append(CGPoint(x: first.x + offsetOpt(off), y: first.y + offsetOpt(off)))
        for i in 1..<points.count {
            ps.append(CGPoint(x: points[i].x + offsetOpt(off), y: points[i].y + offsetOpt(off)))
            if i == points.count - 1 {
                ps.append(CGPoint(x: points[i].x + offsetOpt(off), y: points[i].y + offsetOpt(off)))
            }
        }
        return curveOps(ps)
    }

    /// Smooth curve through `points` (Catmull-Rom), drawn twice unless multi-stroke is disabled.
    public func curve(_ points: [CGPoint]) -> [PathOp] {
        guard points.count >= 2 else { return [] }
        var ops = curveWithOffset(points, offset: 1 * (1 + o.roughness * 0.2))
        if !o.disableMultiStroke {
            ops += alteredSeed().curveWithOffset(points, offset: 1.5 * (1 + o.roughness * 0.22))
        }
        return ops
    }

    /// Cubic from `current` with jittered control points (rough.js `_bezierTo`).
    private func bezierTo(_ c1: CGPoint, _ c2: CGPoint, _ end: CGPoint, from current: CGPoint) -> [PathOp] {
        var ops: [PathOp] = []
        let ros = [o.maxRandomnessOffset == 0 ? 1 : o.maxRandomnessOffset,
                   (o.maxRandomnessOffset == 0 ? 1 : o.maxRandomnessOffset) + 0.3]
        let iterations = o.disableMultiStroke ? 1 : 2
        let pv = o.preserveVertices
        for i in 0..<iterations {
            if i == 0 {
                ops.append(.move(current))
            } else {
                ops.append(.move(CGPoint(x: current.x + (pv ? 0 : offsetOpt(ros[0])),
                                         y: current.y + (pv ? 0 : offsetOpt(ros[0])))))
            }
            let f = pv ? end : CGPoint(x: end.x + offsetOpt(ros[i]), y: end.y + offsetOpt(ros[i]))
            ops.append(.curve(CGPoint(x: c1.x + offsetOpt(ros[i]), y: c1.y + offsetOpt(ros[i])),
                              CGPoint(x: c2.x + offsetOpt(ros[i]), y: c2.y + offsetOpt(ros[i])),
                              f))
        }
        return ops
    }

    /// Polygon with rounded corners: rough straight edges + rough quadratic corners.
    public func roundedPolygon(_ vertices: [CGPoint], radius: CGFloat) -> [PathOp] {
        guard radius > 0 else { return polygon(vertices) }
        let corners = Curves.roundedCorners(vertices, radius: radius)
        var ops: [PathOp] = []
        for i in 0..<corners.count {
            let c = corners[i]
            let next = corners[(i + 1) % corners.count]
            // Corner i as a quadratic a → vertex → b, expressed as a cubic.
            let c1 = c.a + (c.vertex - c.a) * (2.0 / 3.0)
            let c2 = c.b + (c.vertex - c.b) * (2.0 / 3.0)
            ops += bezierTo(c1, c2, c.b, from: c.a)
            if c.b.distance(to: next.a) > 0.5 { ops += doubleLine(c.b, next.a) }
        }
        return ops
    }

    // MARK: Ellipse

    public struct EllipseResult {
        public var ops: [PathOp]
        public var estimatedPoints: [CGPoint]
    }

    private struct EllipseParams { var increment: Double; var rx: Double; var ry: Double }

    private func ellipseParams(width: Double, height: Double) -> EllipseParams {
        let psq = (Double.pi * 2 * (((width / 2) * (width / 2) + (height / 2) * (height / 2)) / 2).squareRoot()).squareRoot()
        let stepCount = ceil(max(o.curveStepCount, (o.curveStepCount / 200.0.squareRoot()) * psq))
        let increment = Double.pi * 2 / stepCount
        var rx = abs(width / 2), ry = abs(height / 2)
        let fitRandomness = 1 - o.curveFitting
        rx += offsetOpt(rx * fitRandomness)
        ry += offsetOpt(ry * fitRandomness)
        return EllipseParams(increment: increment, rx: rx, ry: ry)
    }

    private func ellipsePoints(increment inc0: Double, cx: Double, cy: Double, rx: Double, ry: Double,
                               offset off: Double, overlap: Double) -> (all: [CGPoint], core: [CGPoint]) {
        var core: [CGPoint] = []
        var all: [CGPoint] = []
        if o.roughness == 0 {
            let inc = inc0 / 4
            all.append(CGPoint(x: cx + rx * cos(-inc), y: cy + ry * sin(-inc)))
            var angle = 0.0
            while angle <= .pi * 2 {
                let p = CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
                core.append(p); all.append(p)
                angle += inc
            }
            all.append(CGPoint(x: cx + rx * cos(0), y: cy + ry * sin(0)))
            all.append(CGPoint(x: cx + rx * cos(inc), y: cy + ry * sin(inc)))
        } else {
            let inc = inc0
            let radOffset = offsetOpt(0.5) - .pi / 2
            all.append(CGPoint(x: offsetOpt(off) + cx + 0.9 * rx * cos(radOffset - inc),
                               y: offsetOpt(off) + cy + 0.9 * ry * sin(radOffset - inc)))
            let endAngle = .pi * 2 + radOffset - 0.01
            var angle = radOffset
            while angle < endAngle {
                let p = CGPoint(x: offsetOpt(off) + cx + rx * cos(angle), y: offsetOpt(off) + cy + ry * sin(angle))
                core.append(p); all.append(p)
                angle += inc
            }
            all.append(CGPoint(x: offsetOpt(off) + cx + rx * cos(radOffset + .pi * 2 + overlap * 0.5),
                               y: offsetOpt(off) + cy + ry * sin(radOffset + .pi * 2 + overlap * 0.5)))
            all.append(CGPoint(x: offsetOpt(off) + cx + 0.98 * rx * cos(radOffset + overlap),
                               y: offsetOpt(off) + cy + 0.98 * ry * sin(radOffset + overlap)))
            all.append(CGPoint(x: offsetOpt(off) + cx + 0.9 * rx * cos(radOffset + overlap * 0.5),
                               y: offsetOpt(off) + cy + 0.9 * ry * sin(radOffset + overlap * 0.5)))
        }
        return (all, core)
    }

    private func ellipse(_ cx: Double, _ cy: Double, params ep: EllipseParams) -> EllipseResult {
        let overlap = ep.increment * offset(0.1, offset(0.4, 1))
        let (ap1, cp1) = ellipsePoints(increment: ep.increment, cx: cx, cy: cy, rx: ep.rx, ry: ep.ry,
                                       offset: 1, overlap: overlap)
        var ops = curveOps(ap1)
        if !o.disableMultiStroke && o.roughness != 0 {
            let (ap2, _) = ellipsePoints(increment: ep.increment, cx: cx, cy: cy, rx: ep.rx, ry: ep.ry,
                                         offset: 1.5, overlap: 0)
            ops += curveOps(ap2)
        }
        return EllipseResult(ops: ops, estimatedPoints: cp1)
    }

    /// Ellipse centered at `center`. Returns the stroke ops plus points approximating the
    /// outline (used for hachure fill) and, when requested, a solid fill path.
    public func ellipse(center: CGPoint, width: Double, height: Double, solidFill: Bool = false)
        -> (stroke: EllipseResult, fill: [PathOp]?) {
        let params = ellipseParams(width: width, height: height)
        let stroke = ellipse(center.x, center.y, params: params)
        let fill = solidFill ? ellipse(center.x, center.y, params: params).ops : nil
        return (stroke, fill)
    }

    // MARK: Fills

    public func solidFill(_ polygon: [CGPoint]) -> [PathOp] {
        guard polygon.count > 2 else { return [] }
        let off = o.maxRandomnessOffset
        var ops: [PathOp] = [.move(CGPoint(x: polygon[0].x + offsetOpt(off), y: polygon[0].y + offsetOpt(off)))]
        for p in polygon.dropFirst() {
            ops.append(.line(CGPoint(x: p.x + offsetOpt(off), y: p.y + offsetOpt(off))))
        }
        return ops
    }

    /// Hachure (or cross-hatch) lines clipped to the polygon, each drawn as a rough line.
    public func hachureFill(_ polygon: [CGPoint], crossHatch: Bool) -> [PathOp] {
        var gap = o.hachureGap
        if gap < 0 { gap = o.strokeWidth * 4 }
        gap = max(gap, 0.1)
        var lines = Hachure.lines(polygon: polygon, angle: o.hachureAngle + 90, gap: gap)
        if crossHatch {
            lines += Hachure.lines(polygon: polygon, angle: o.hachureAngle + 180, gap: gap)
        }
        var ops: [PathOp] = []
        for l in lines { ops += doubleLine(l.0, l.1, filling: true) }
        return ops
    }
}
