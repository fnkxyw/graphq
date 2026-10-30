import CoreGraphics
import Foundation

public enum Intersections {
    /// First intersection (closest to `from`) of the scene segment `from`→`to`
    /// with the outline of `e`, or nil if the segment does not cross it.
    public static func outline(of e: Element, from: CGPoint, to: CGPoint) -> CGPoint? {
        let a = e.toLocal(from), b = e.toLocal(to)
        let t: CGFloat?
        if e.type == .ellipse {
            t = ellipseParameter(a, b, rx: e.width / 2, ry: e.height / 2, center: CGPoint(x: e.width / 2, y: e.height / 2))
        } else {
            t = polygonParameter(a, b, polygon: e.localOutline)
        }
        guard let t else { return nil }
        return e.toScene(a.lerp(to: b, t))
    }

    /// Smallest t in [0,1] where segment a→b crosses the closed polygon.
    static func polygonParameter(_ a: CGPoint, _ b: CGPoint, polygon: [CGPoint]) -> CGFloat? {
        guard polygon.count >= 2 else { return nil }
        var best: CGFloat?
        for i in 0..<polygon.count {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            guard let t = Segment.intersectionParameter(a, b, p, q) else { continue }
            if let current = best, current <= t { continue }
            best = t
        }
        return best
    }

    /// Smallest t in [0,1] where segment a→b crosses the axis-aligned ellipse.
    static func ellipseParameter(_ a: CGPoint, _ b: CGPoint, rx: CGFloat, ry: CGFloat, center: CGPoint) -> CGFloat? {
        guard rx > 0, ry > 0 else { return nil }
        // Scale into the unit circle and solve |p0 + t d|^2 = 1.
        let p0 = CGPoint(x: (a.x - center.x) / rx, y: (a.y - center.y) / ry)
        let p1 = CGPoint(x: (b.x - center.x) / rx, y: (b.y - center.y) / ry)
        let d = p1 - p0
        let qa = d.dot(d), qb = 2 * p0.dot(d), qc = p0.dot(p0) - 1
        guard qa > 0 else { return nil }
        let disc = qb * qb - 4 * qa * qc
        guard disc >= 0 else { return nil }
        let sq = disc.squareRoot()
        let denom: CGFloat = 2 * qa
        let t1: CGFloat = (-qb - sq) / denom
        let t2: CGFloat = (-qb + sq) / denom
        if t1 >= 0 && t1 <= 1 { return t1 }
        if t2 >= 0 && t2 <= 1 { return t2 }
        return nil
    }
}
