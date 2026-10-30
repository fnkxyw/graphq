import CoreGraphics
import Foundation

/// A guide line drawn while snapping (scene coordinates).
public struct SnapGuide: Hashable, Sendable {
    public var from: CGPoint
    public var to: CGPoint
    public init(from: CGPoint, to: CGPoint) { self.from = from; self.to = to }
}

public struct SnapResult: Sendable {
    public var offset: CGPoint
    public var guides: [SnapGuide]
    public static let none = SnapResult(offset: .zero, guides: [])
}

/// Object snapping: aligns edges and centers of the moving box with nearby elements.
public enum Snapping {
    public static let gridSize: CGFloat = 20

    public static func snapToGrid(_ p: CGPoint, grid: CGFloat = gridSize) -> CGPoint {
        CGPoint(x: (p.x / grid).rounded() * grid, y: (p.y / grid).rounded() * grid)
    }

    private static func xs(_ r: CGRect) -> [CGFloat] { [r.minX, r.midX, r.maxX] }
    private static func ys(_ r: CGRect) -> [CGFloat] { [r.minY, r.midY, r.maxY] }

    /// Snaps a moving rectangle to the edges/centers of `references`.
    public static func snap(_ moving: CGRect, to references: [CGRect], threshold: CGFloat) -> SnapResult {
        let dx = bestDelta(xs(moving), references.map(xs), threshold)
        let dy = bestDelta(ys(moving), references.map(ys), threshold)
        let offset = CGPoint(x: dx ?? 0, y: dy ?? 0)
        let snapped = moving.offsetBy(dx: offset.x, dy: offset.y)
        return SnapResult(offset: offset, guides: guides(for: snapped, references: references,
                                                         snapX: dx != nil, snapY: dy != nil))
    }

    /// Snaps a single point (used while drawing/resizing).
    public static func snap(point p: CGPoint, to references: [CGRect], threshold: CGFloat) -> SnapResult {
        snap(CGRect(origin: p, size: .zero), to: references, threshold: threshold)
    }

    private static func bestDelta(_ moving: [CGFloat], _ refs: [[CGFloat]], _ threshold: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for ref in refs {
            for r in ref {
                for m in moving {
                    let d = r - m
                    if abs(d) <= threshold && abs(d) < abs(best ?? .infinity) { best = d }
                }
            }
        }
        return best
    }

    private static func guides(for box: CGRect, references: [CGRect], snapX: Bool, snapY: Bool) -> [SnapGuide] {
        var result: [SnapGuide] = []
        let eps: CGFloat = 0.5
        if snapX {
            for x in xs(box) {
                let matching = references.filter { r in xs(r).contains { abs($0 - x) < eps } }
                guard !matching.isEmpty else { continue }
                let minY = matching.map(\.minY).min()!.minimum(box.minY)
                let maxY = matching.map(\.maxY).max()!.maximum(box.maxY)
                result.append(SnapGuide(from: CGPoint(x: x, y: minY), to: CGPoint(x: x, y: maxY)))
            }
        }
        if snapY {
            for y in ys(box) {
                let matching = references.filter { r in ys(r).contains { abs($0 - y) < eps } }
                guard !matching.isEmpty else { continue }
                let minX = matching.map(\.minX).min()!.minimum(box.minX)
                let maxX = matching.map(\.maxX).max()!.maximum(box.maxX)
                result.append(SnapGuide(from: CGPoint(x: minX, y: y), to: CGPoint(x: maxX, y: y)))
            }
        }
        return result
    }
}

private extension CGFloat {
    func minimum(_ o: CGFloat) -> CGFloat { Swift.min(self, o) }
    func maximum(_ o: CGFloat) -> CGFloat { Swift.max(self, o) }
}
