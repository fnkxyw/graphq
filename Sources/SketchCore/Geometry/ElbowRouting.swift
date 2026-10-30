import CoreGraphics
import Foundation

/// Axis-aligned direction used by elbow connectors.
public enum Heading: Sendable, Equatable {
    case up, down, left, right

    public var vector: CGPoint {
        switch self {
        case .up: CGPoint(x: 0, y: -1)
        case .down: CGPoint(x: 0, y: 1)
        case .left: CGPoint(x: -1, y: 0)
        case .right: CGPoint(x: 1, y: 0)
        }
    }

    public var isHorizontal: Bool { self == .left || self == .right }
}

/// Orthogonal routing for elbow arrows. Each end leaves its point along a heading
/// (for bound ends: the outward normal of the side it is attached to), runs a short
/// stub, and the stubs are joined with at most two bends.
public enum ElbowRouter {
    public static let stub: CGFloat = 24

    /// Heading from `p` toward `q` along the dominant axis.
    public static func heading(from p: CGPoint, toward q: CGPoint) -> Heading {
        let d = q - p
        if abs(d.x) >= abs(d.y) { return d.x >= 0 ? .right : .left }
        return d.y >= 0 ? .down : .up
    }

    /// Side of `rect` that faces `q` (normalized by the rect's aspect).
    public static func side(of rect: CGRect, facing q: CGPoint) -> Heading {
        let dx = (q.x - rect.midX) / max(rect.width / 2, 1)
        let dy = (q.y - rect.midY) / max(rect.height / 2, 1)
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .down : .up
    }

    /// Point on the facing side of `rect`, at the focus coordinate, pushed out by `gap`.
    public static func attachPoint(on rect: CGRect, side: Heading, focus: CGPoint, gap: CGFloat) -> CGPoint {
        let fx = min(max(focus.x, rect.minX), rect.maxX)
        let fy = min(max(focus.y, rect.minY), rect.maxY)
        switch side {
        case .left: return CGPoint(x: rect.minX - gap, y: fy)
        case .right: return CGPoint(x: rect.maxX + gap, y: fy)
        case .up: return CGPoint(x: fx, y: rect.minY - gap)
        case .down: return CGPoint(x: fx, y: rect.maxY + gap)
        }
    }

    /// Orthogonal polyline from `start` to `end`.
    /// `endHeading` points *out* of the end (the arrow arrives moving opposite to it).
    public static func route(start: CGPoint, startHeading sh: Heading, end: CGPoint, endHeading eh: Heading) -> [CGPoint] {
        let s1 = start + sh.vector * stub
        let e1 = end + eh.vector * stub
        var pts: [CGPoint] = [start, s1]

        func interval(_ h: Heading, _ v: CGFloat, horizontal: Bool) -> (CGFloat, CGFloat) {
            // Allowed range for the shared coordinate so the stub never doubles back.
            if horizontal {
                if h == .right { return (v, .infinity) }
                if h == .left { return (-.infinity, v) }
            } else {
                if h == .down { return (v, .infinity) }
                if h == .up { return (-.infinity, v) }
            }
            return (-.infinity, .infinity)
        }

        if sh.isHorizontal == eh.isHorizontal {
            let horizontal = sh.isHorizontal
            let a = interval(sh, horizontal ? s1.x : s1.y, horizontal: horizontal)
            let b = interval(eh, horizontal ? e1.x : e1.y, horizontal: horizontal)
            let lo = max(a.0, b.0), hi = min(a.1, b.1)
            if lo <= hi {
                let mid = horizontal ? (s1.x + e1.x) / 2 : (s1.y + e1.y) / 2
                let m = min(max(mid, lo), hi)
                if horizontal {
                    pts += [CGPoint(x: m, y: s1.y), CGPoint(x: m, y: e1.y)]
                } else {
                    pts += [CGPoint(x: s1.x, y: m), CGPoint(x: e1.x, y: m)]
                }
            } else if horizontal {
                let my = (s1.y + e1.y) / 2
                pts += [CGPoint(x: s1.x, y: my), CGPoint(x: e1.x, y: my)]
            } else {
                let mx = (s1.x + e1.x) / 2
                pts += [CGPoint(x: mx, y: s1.y), CGPoint(x: mx, y: e1.y)]
            }
        } else {
            // One bend if the corner keeps both stubs moving forward, otherwise two.
            let corner = sh.isHorizontal ? CGPoint(x: e1.x, y: s1.y) : CGPoint(x: s1.x, y: e1.y)
            let firstOK = (corner - s1).dot(sh.vector) >= 0
            let secondOK = (e1 - corner).dot(-eh.vector) >= 0
            if firstOK && secondOK {
                pts.append(corner)
            } else if sh.isHorizontal {
                let my = (s1.y + e1.y) / 2
                pts += [CGPoint(x: s1.x, y: my), CGPoint(x: e1.x, y: my)]
            } else {
                let mx = (s1.x + e1.x) / 2
                pts += [CGPoint(x: mx, y: s1.y), CGPoint(x: mx, y: e1.y)]
            }
        }
        pts += [e1, end]
        return simplify(pts)
    }

    /// Drops duplicate and collinear interior points.
    static func simplify(_ input: [CGPoint]) -> [CGPoint] {
        var pts: [CGPoint] = []
        for p in input where pts.last.map({ !$0.isClose(to: p, epsilon: 0.01) }) ?? true {
            pts.append(p)
        }
        var i = 1
        while i + 1 < pts.count {
            let a = pts[i - 1], b = pts[i], c = pts[i + 1]
            if abs((b - a).cross(c - b)) < 0.01 && (b - a).dot(c - b) >= 0 {
                pts.remove(at: i)
            } else {
                i += 1
            }
        }
        return pts
    }
}

public extension Element {
    /// Middle of the drawn path (by length), in local coordinates — where arrow labels sit.
    var labelAnchor: CGPoint {
        let path = localPath
        guard path.count >= 2 else { return path.first ?? .zero }
        let total = zip(path, path.dropFirst()).reduce(CGFloat(0)) { $0 + $1.0.distance(to: $1.1) }
        var remaining = total / 2
        for (a, b) in zip(path, path.dropFirst()) {
            let d = a.distance(to: b)
            if d >= remaining, d > 0 { return a.lerp(to: b, remaining / d) }
            remaining -= d
        }
        return path[path.count - 1]
    }

    /// Rough label size for hit-testing (the renderer measures precisely).
    var approximateLabelSize: CGSize {
        let lines = text.components(separatedBy: "\n")
        let longest = lines.map(\.count).max() ?? 0
        return CGSize(width: CGFloat(longest) * fontSize * 0.55 + 8,
                      height: CGFloat(lines.count) * fontSize * 1.25 + 4)
    }

    /// Height reserved above a frame for its name.
    static let frameTitleHeight: CGFloat = 22

    /// Clickable title strip above a frame (local coordinates).
    var frameTitleRect: CGRect {
        let chars = CGFloat(max(text.count, 5))
        let w: CGFloat = min(width, chars * 8 + 12)
        return CGRect(x: 0, y: -Element.frameTitleHeight, width: w, height: Element.frameTitleHeight - 2)
    }
}
