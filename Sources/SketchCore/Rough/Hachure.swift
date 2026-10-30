import CoreGraphics
import Foundation

/// Scan-line hachure generation (rough.js `polygonHachureLines`).
/// The polygon is rotated so hachures become horizontal, filled with an active-edge
/// scan line, and the resulting segments are rotated back.
public enum Hachure {
    public static func lines(polygon: [CGPoint], angle degrees: Double, gap: Double) -> [(CGPoint, CGPoint)] {
        guard polygon.count >= 3, gap > 0 else { return [] }
        let rad = degrees * .pi / 180
        let rotated = polygon.map { $0.rotated(around: .zero, by: rad) }
        return scan(rotated, gap: gap).map {
            ($0.0.rotated(around: .zero, by: -rad), $0.1.rotated(around: .zero, by: -rad))
        }
    }

    private struct Edge {
        var ymin: Double
        var ymax: Double
        var x: Double
        var islope: Double
    }

    private static func scan(_ input: [CGPoint], gap: Double) -> [(CGPoint, CGPoint)] {
        var vertices = input
        if let f = vertices.first, let l = vertices.last, !f.isClose(to: l) { vertices.append(f) }

        var edges: [Edge] = []
        for i in 0..<(vertices.count - 1) {
            let p1 = vertices[i], p2 = vertices[i + 1]
            guard p1.y != p2.y else { continue }
            let ymin = min(p1.y, p2.y)
            edges.append(Edge(ymin: ymin, ymax: max(p1.y, p2.y),
                              x: ymin == p1.y ? p1.x : p2.x,
                              islope: (p2.x - p1.x) / (p2.y - p1.y)))
        }
        edges.sort { a, b in
            if a.ymin != b.ymin { return a.ymin < b.ymin }
            if a.x != b.x { return a.x < b.x }
            return a.ymax < b.ymax
        }
        guard !edges.isEmpty else { return [] }

        var lines: [(CGPoint, CGPoint)] = []
        var active: [Edge] = []
        var y = edges[0].ymin
        var pending = edges[...]
        // Safety bound: a polygon can't need more scan lines than its height / gap.
        let maxIterations = Int((edges.map(\.ymax).max()! - y) / gap) + 2
        var iteration = 0
        while (!active.isEmpty || !pending.isEmpty) && iteration <= maxIterations {
            while let e = pending.first, e.ymin <= y {
                active.append(e)
                pending = pending.dropFirst()
            }
            active.removeAll { $0.ymax <= y }
            active.sort { $0.x < $1.x }
            if active.count > 1 {
                var i = 0
                while i + 1 < active.count {
                    lines.append((CGPoint(x: active[i].x.rounded(), y: y), CGPoint(x: active[i + 1].x.rounded(), y: y)))
                    i += 2
                }
            }
            y += gap
            for i in active.indices { active[i].x += gap * active[i].islope }
            iteration += 1
        }
        return lines
    }
}
