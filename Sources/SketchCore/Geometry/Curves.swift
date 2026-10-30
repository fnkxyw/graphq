import CoreGraphics
import Foundation

public struct CubicBezier: Hashable, Sendable {
    public var p0, c1, c2, p3: CGPoint

    public init(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint) {
        self.p0 = p0; self.c1 = c1; self.c2 = c2; self.p3 = p3
    }

    public func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
        )
    }
}

public enum Curves {
    /// Catmull-Rom spline through `points` as cubic Béziers (tension 0, same as rough.js `curve`).
    public static func catmullRom(_ points: [CGPoint]) -> [CubicBezier] {
        guard points.count >= 2 else { return [] }
        var result: [CubicBezier] = []
        result.reserveCapacity(points.count - 1)
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let c1 = p1 + (p2 - p0) / 6
            let c2 = p2 - (p3 - p1) / 6
            result.append(CubicBezier(p1, c1, c2, p2))
        }
        return result
    }

    /// Flattens a curve through `points` into a polyline.
    public static func sampleCatmullRom(_ points: [CGPoint], stepsPerSegment: Int = 12) -> [CGPoint] {
        let beziers = catmullRom(points)
        guard let first = beziers.first else { return points }
        var out: [CGPoint] = [first.p0]
        for bz in beziers {
            for s in 1...stepsPerSegment {
                out.append(bz.point(at: CGFloat(s) / CGFloat(stepsPerSegment)))
            }
        }
        return out
    }

    /// Corner data for a polygon with rounded corners: for each vertex, the points where
    /// the straight edges end (`a` on the incoming edge, `b` on the outgoing edge).
    public struct RoundedCorner: Sendable {
        public var a: CGPoint
        public var vertex: CGPoint
        public var b: CGPoint
    }

    public static func roundedCorners(_ vertices: [CGPoint], radius: CGFloat) -> [RoundedCorner] {
        let n = vertices.count
        return (0..<n).map { i in
            let v = vertices[i]
            let prev = vertices[(i + n - 1) % n]
            let next = vertices[(i + 1) % n]
            let inLen = v.distance(to: prev), outLen = v.distance(to: next)
            let r = min(radius, inLen / 2, outLen / 2)
            let a = inLen == 0 ? v : v + (prev - v) * (r / inLen)
            let b = outLen == 0 ? v : v + (next - v) * (r / outLen)
            return RoundedCorner(a: a, vertex: v, b: b)
        }
    }

    /// Polyline approximation of a rounded polygon (corners as quadratic curves).
    public static func roundedPolygonPoints(_ vertices: [CGPoint], radius: CGFloat, steps: Int = 6) -> [CGPoint] {
        guard radius > 0 else { return vertices }
        var out: [CGPoint] = []
        for c in roundedCorners(vertices, radius: radius) {
            for s in 0...steps {
                let t = CGFloat(s) / CGFloat(steps)
                // Quadratic Bézier a -> vertex -> b
                let p = c.a * ((1 - t) * (1 - t)) + c.vertex * (2 * (1 - t) * t) + c.b * (t * t)
                out.append(p)
            }
        }
        return out
    }

    /// Polygon approximation of an ellipse inscribed in `rect`.
    public static func ellipsePoints(in rect: CGRect, steps: Int = 48) -> [CGPoint] {
        let c = rect.center, rx = rect.width / 2, ry = rect.height / 2
        return (0..<steps).map { i in
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            return CGPoint(x: c.x + rx * cos(t), y: c.y + ry * sin(t))
        }
    }
}
