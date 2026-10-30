import CoreGraphics
import Foundation

/// Uniform-grid spatial hash over element AABBs. O(1) updates, which matters
/// during drags where the moved elements change every frame.
public struct SpatialIndex: Sendable {
    private struct Cell: Hashable { var x: Int; var y: Int }

    public let cellSize: CGFloat
    private var cells: [Cell: Set<String>] = [:]
    private var entries: [String: (rect: CGRect, cells: [Cell])] = [:]
    /// Elements too large to bucket sensibly are kept in a flat list.
    private var oversized: Set<String> = []
    private let maxCellsPerItem = 256

    public init(cellSize: CGFloat = 256) { self.cellSize = cellSize }

    public var count: Int { entries.count }

    public func rect(for id: String) -> CGRect? { entries[id]?.rect }

    private func cellRange(_ r: CGRect) -> (ClosedRange<Int>, ClosedRange<Int>) {
        let x0 = Int(floor(r.minX / cellSize)), x1 = Int(floor(r.maxX / cellSize))
        let y0 = Int(floor(r.minY / cellSize)), y1 = Int(floor(r.maxY / cellSize))
        return (x0...max(x0, x1), y0...max(y0, y1))
    }

    public mutating func insert(_ id: String, rect: CGRect) {
        remove(id)
        guard !rect.isNull, rect.minX.isFinite, rect.maxY.isFinite else { return }
        let (xr, yr) = cellRange(rect)
        if xr.count * yr.count > maxCellsPerItem {
            oversized.insert(id)
            entries[id] = (rect, [])
            return
        }
        var list: [Cell] = []
        list.reserveCapacity(xr.count * yr.count)
        for cx in xr { for cy in yr {
            let c = Cell(x: cx, y: cy)
            cells[c, default: []].insert(id)
            list.append(c)
        } }
        entries[id] = (rect, list)
    }

    public mutating func remove(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        oversized.remove(id)
        for c in entry.cells {
            cells[c]?.remove(id)
            if cells[c]?.isEmpty == true { cells[c] = nil }
        }
    }

    public mutating func removeAll() {
        cells.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
        oversized.removeAll()
    }

    /// Ids whose AABB intersects `rect`.
    public func query(_ rect: CGRect) -> Set<String> {
        var result = Set<String>()
        guard !rect.isNull else { return result }
        let (xr, yr) = cellRange(rect)
        if xr.count * yr.count > cells.count {
            // Huge query (zoomed far out): scan entries instead of empty cells.
            for (id, e) in entries where e.rect.intersects(rect) || e.rect.width == 0 || e.rect.height == 0 {
                if e.rect.insetBy(dx: -0.5, dy: -0.5).intersects(rect) { result.insert(id) }
            }
            return result
        }
        for cx in xr { for cy in yr {
            guard let ids = cells[Cell(x: cx, y: cy)] else { continue }
            for id in ids where !result.contains(id) {
                if let r = entries[id]?.rect, r.insetBy(dx: -0.5, dy: -0.5).intersects(rect) { result.insert(id) }
            }
        } }
        for id in oversized where entries[id]!.rect.intersects(rect) { result.insert(id) }
        return result
    }

    /// Ids whose AABB contains `point` (expanded by `radius`).
    public func query(point: CGPoint, radius: CGFloat) -> Set<String> {
        query(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}
