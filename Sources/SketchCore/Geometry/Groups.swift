import CoreGraphics
import Foundation

public enum Groups {
    /// The group that acts as a selection unit for `e`. When the user has "entered"
    /// a group (`editingGroupId`), units are the next level inside it.
    public static func selectionGroup(of e: Element, editingGroupId: String?) -> String? {
        guard let editing = editingGroupId, let idx = e.groupIds.firstIndex(of: editing) else {
            return e.groupIds.last
        }
        return idx > 0 ? e.groupIds[idx - 1] : nil
    }

    /// Expands a set of ids so whole groups are selected together.
    public static func expand(_ ids: Set<String>, in elements: [Element], editingGroupId: String?) -> Set<String> {
        var groups = Set<String>()
        for e in elements where ids.contains(e.id) {
            if let g = selectionGroup(of: e, editingGroupId: editingGroupId) { groups.insert(g) }
        }
        guard !groups.isEmpty else { return ids }
        var result = ids
        for e in elements where e.groupIds.contains(where: groups.contains) { result.insert(e.id) }
        return result
    }

    /// Partitions ids into units (whole outermost groups or single elements) for align/distribute.
    public static func units(_ ids: Set<String>, in elements: [Element]) -> [[String]] {
        var byGroup: [String: [String]] = [:]
        var order: [String] = []
        for e in elements where ids.contains(e.id) {
            let key = e.groupIds.last ?? "#\(e.id)"
            if byGroup[key] == nil { order.append(key) }
            byGroup[key, default: []].append(e.id)
        }
        return order.map { byGroup[$0]! }
    }

    /// Copies elements with fresh ids; group ids and bindings are remapped consistently
    /// and references to elements outside the copied set are dropped.
    public static func duplicate(_ source: [Element], offset: CGPoint) -> [Element] {
        var idMap: [String: String] = [:]
        var groupMap: [String: String] = [:]
        for e in source { idMap[e.id] = ElementID.make() }
        return source.map { e in
            var c = e
            c.id = idMap[e.id]!
            c.seed = ElementID.makeSeed()
            c.version = 1
            c.versionNonce = ElementID.makeSeed()
            c.locked = false
            c.x += offset.x
            c.y += offset.y
            c.groupIds = e.groupIds.map { g in
                if let m = groupMap[g] { return m }
                let n = ElementID.make()
                groupMap[g] = n
                return n
            }
            c.boundElements = e.boundElements.compactMap { idMap[$0] }
            if let b = e.startBinding {
                c.startBinding = idMap[b.elementId].map { PointBinding(elementId: $0, focus: b.focus, gap: b.gap) }
            }
            if let b = e.endBinding {
                c.endBinding = idMap[b.elementId].map { PointBinding(elementId: $0, focus: b.focus, gap: b.gap) }
            }
            return c
        }
    }
}
