import CoreGraphics
import Foundation

// Small vector toolkit on CGPoint used across geometry, rough and freehand code.
public extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x / s, y: a.y / s) }
    static prefix func - (a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }
    static func -= (a: inout CGPoint, b: CGPoint) { a = a - b }

    var length: CGFloat { hypot(x, y) }
    var lengthSquared: CGFloat { x * x + y * y }

    var normalized: CGPoint {
        let l = length
        return l == 0 ? self : CGPoint(x: x / l, y: y / l)
    }

    /// Perpendicular vector (rotated -90° in a y-down space).
    var perpendicular: CGPoint { CGPoint(x: y, y: -x) }

    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }
    func cross(_ o: CGPoint) -> CGFloat { x * o.y - y * o.x }
    func distance(to o: CGPoint) -> CGFloat { hypot(x - o.x, y - o.y) }
    func distanceSquared(to o: CGPoint) -> CGFloat { (x - o.x) * (x - o.x) + (y - o.y) * (y - o.y) }

    func lerp(to o: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: x + (o.x - x) * t, y: y + (o.y - y) * t) }

    /// Rotates around `center` by `angle` radians.
    func rotated(around center: CGPoint, by angle: CGFloat) -> CGPoint {
        if angle == 0 { return self }
        let s = sin(angle), c = cos(angle)
        let dx = x - center.x, dy = y - center.y
        return CGPoint(x: center.x + dx * c - dy * s, y: center.y + dx * s + dy * c)
    }

    func isClose(to o: CGPoint, epsilon: CGFloat = 1e-6) -> Bool {
        abs(x - o.x) < epsilon && abs(y - o.y) < epsilon
    }
}

public extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    /// Bounding rect of a set of points; `.null` when empty.
    init(enclosing points: [CGPoint]) {
        guard let first = points.first else { self = .null; return }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var corners: [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }
}

public enum Segment {
    /// Shortest distance from `p` to the segment `a`–`b`.
    public static func distance(from p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = b - a
        let len2 = ab.lengthSquared
        if len2 == 0 { return p.distance(to: a) }
        let t = max(0, min(1, (p - a).dot(ab) / len2))
        return p.distance(to: a + ab * t)
    }

    /// Intersection point of segments p1–p2 and p3–p4, if any.
    public static func intersection(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> CGPoint? {
        let r = p2 - p1, s = p4 - p3
        let denom = r.cross(s)
        if abs(denom) < 1e-12 { return nil }
        let t = (p3 - p1).cross(s) / denom
        let u = (p3 - p1).cross(r) / denom
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return p1 + r * t
    }

    /// Parameter `t` (0...1) along p1–p2 of the intersection with p3–p4.
    public static func intersectionParameter(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> CGFloat? {
        let r = p2 - p1, s = p4 - p3
        let denom = r.cross(s)
        if abs(denom) < 1e-12 { return nil }
        let t = (p3 - p1).cross(s) / denom
        let u = (p3 - p1).cross(r) / denom
        guard t >= 0, t <= 1, u >= 0, u <= 1 else { return nil }
        return t
    }
}

public enum Polygon {
    /// Even-odd point-in-polygon test.
    public static func contains(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xCross = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    public static func distanceToOutline(_ poly: [CGPoint], _ p: CGPoint, closed: Bool = true) -> CGFloat {
        guard poly.count > 1 else { return poly.first.map { p.distance(to: $0) } ?? .infinity }
        var best = CGFloat.infinity
        for i in 0..<(poly.count - 1) {
            best = min(best, Segment.distance(from: p, poly[i], poly[i + 1]))
        }
        if closed, let f = poly.first, let l = poly.last {
            best = min(best, Segment.distance(from: p, l, f))
        }
        return best
    }
}
