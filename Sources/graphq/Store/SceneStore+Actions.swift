import CoreGraphics
import Foundation
import SketchCore
import SketchRender

/// High-level editing commands. Each one is a single undo step.
extension SceneStore {
    // MARK: Selection

    func select(_ ids: Set<String>) {
        selection = Groups.expand(ids, in: elements, editingGroupId: editingGroupId)
    }

    func selectAll() {
        editingGroupId = nil
        selection = Set(elements.filter { !$0.locked }.map(\.id))
    }

    func clearSelection() {
        selection = []
        editingGroupId = nil
    }

    var selectionBounds: CGRect { SceneGeometry.bounds(of: selectedElements) }

    // MARK: Delete / duplicate

    func deleteSelection() {
        let ids = selection.filter { element($0)?.locked == false }
        guard !ids.isEmpty else { return }
        perform("Delete") { remove(Set(ids)) }
    }

    func duplicateSelection(offset: CGPoint = CGPoint(x: 12, y: 12)) {
        let source = elements.filter { selection.contains($0.id) }
        guard !source.isEmpty else { return }
        perform("Duplicate") {
            let copies = Groups.duplicate(source, offset: offset)
            insert(copies)
            selection = Set(copies.map(\.id))
        }
    }

    /// Inserts copies right above their originals (Option-drag) and selects them.
    @discardableResult
    func duplicateSelectionInPlace() -> [Element] {
        let source = elements.filter { selection.contains($0.id) }
        let copies = Groups.duplicate(source, offset: .zero)
        insert(copies)
        selection = Set(copies.map(\.id))
        return copies
    }

    // MARK: Moving

    /// Moves elements by `delta`, detaching arrows from shapes that stay behind
    /// and re-aiming arrows bound to the moved shapes.
    func move(_ ids: Set<String>, by delta: CGPoint) {
        for id in ids {
            update(id) { $0.move(by: delta) }
        }
        detachArrows(movedIds: ids)
        refreshBindings(for: ids)
    }

    /// Arrows that move without their bound target lose that binding.
    func detachArrows(movedIds ids: Set<String>) {
        for id in ids {
            guard let e = element(id), e.type.isLinear else { continue }
            if let b = e.startBinding, !ids.contains(b.elementId) { setBinding(nil, end: .start, arrowId: id) }
            if let b = e.endBinding, !ids.contains(b.elementId) { setBinding(nil, end: .end, arrowId: id) }
        }
    }

    func nudgeSelection(_ delta: CGPoint) {
        let ids = selection.filter { element($0)?.locked == false }
        guard !ids.isEmpty else { return }
        perform("Move") { move(Set(ids), by: delta) }
    }

    // MARK: Groups

    func groupSelection() {
        guard selection.count > 1 else { return }
        let gid = ElementID.make()
        perform("Group") {
            for id in selection {
                update(id) { e in
                    if let editing = editingGroupId, let idx = e.groupIds.firstIndex(of: editing) {
                        // Grouping inside an entered group nests the new group under it.
                        e.groupIds.insert(gid, at: idx)
                    } else {
                        e.groupIds.append(gid)
                    }
                }
            }
        }
    }

    func ungroupSelection() {
        let selected = selectedElements
        let groups = Set(selected.compactMap { Groups.selectionGroup(of: $0, editingGroupId: editingGroupId) })
        guard !groups.isEmpty else { return }
        perform("Ungroup") {
            for e in selected {
                update(e.id) { $0.groupIds.removeAll { groups.contains($0) } }
            }
        }
    }

    var canUngroup: Bool {
        selectedElements.contains { Groups.selectionGroup(of: $0, editingGroupId: editingGroupId) != nil }
    }

    // MARK: Z-order

    enum ZOrder { case forward, backward, front, back }

    func arrange(_ order: ZOrder) {
        guard !selection.isEmpty else { return }
        var list = elements
        let sel = selection
        switch order {
        case .front:
            list = list.filter { !sel.contains($0.id) } + list.filter { sel.contains($0.id) }
        case .back:
            list = list.filter { sel.contains($0.id) } + list.filter { !sel.contains($0.id) }
        case .forward:
            var i = list.count - 2
            while i >= 0 {
                if sel.contains(list[i].id) && !sel.contains(list[i + 1].id) { list.swapAt(i, i + 1) }
                i -= 1
            }
        case .backward:
            var i = 1
            while i < list.count {
                if sel.contains(list[i].id) && !sel.contains(list[i - 1].id) { list.swapAt(i, i - 1) }
                i += 1
            }
        }
        guard list.map(\.id) != elements.map(\.id) else { return }
        let names: [ZOrder: String] = [.forward: "Bring Forward", .backward: "Send Backward",
                                       .front: "Bring to Front", .back: "Send to Back"]
        perform(names[order]!) { reorder(list) }
    }

    // MARK: Align / distribute

    func align(_ mode: AlignMode) {
        let units = Groups.units(selection, in: elements)
        guard units.count > 1 else { return }
        let boxes = units.map { unit in SceneGeometry.bounds(of: unit.compactMap(element)) }
        let offsets = Alignment.align(boxes, mode)
        perform("Align") { applyOffsets(units, offsets) }
    }

    func distribute(_ axis: DistributeAxis) {
        let units = Groups.units(selection, in: elements)
        guard units.count > 2 else { return }
        let boxes = units.map { unit in SceneGeometry.bounds(of: unit.compactMap(element)) }
        let offsets = Alignment.distribute(boxes, axis)
        perform("Distribute") { applyOffsets(units, offsets) }
    }

    private func applyOffsets(_ units: [[String]], _ offsets: [CGPoint]) {
        var moved = Set<String>()
        for (unit, off) in zip(units, offsets) where off != .zero {
            for id in unit where element(id)?.locked == false {
                update(id) { $0.move(by: off) }
                moved.insert(id)
            }
        }
        detachArrows(movedIds: moved)
        refreshBindings(for: moved)
    }

    // MARK: Lock

    var selectionIsLocked: Bool { !selectedElements.isEmpty && selectedElements.allSatisfy(\.locked) }

    func toggleLock() {
        guard !selection.isEmpty else { return }
        let lock = !selectionIsLocked
        perform(lock ? "Lock" : "Unlock") {
            for id in selection { update(id) { $0.locked = lock } }
        }
    }

    func unlockAll() {
        let locked = elements.filter(\.locked).map(\.id)
        guard !locked.isEmpty else { return }
        perform("Unlock All") {
            for id in locked { update(id) { $0.locked = false } }
            selection = Set(locked)
        }
    }

    // MARK: Style

    /// Applies a style change to the selection as one undo step and re-fits text.
    func applyStyle(_ name: String, to ids: Set<String>? = nil, _ body: (inout Element) -> Void) {
        let targets = ids ?? selection
        guard !targets.isEmpty else { return }
        perform(name) {
            for id in targets {
                update(id) { e in
                    body(&e)
                    TextFitter.fit(&e)
                }
            }
            refreshBindings(for: targets)
        }
    }

    /// Live variant of `applyStyle` for continuous controls.
    func applyStyleLive(_ name: String, _ body: (inout Element) -> Void) {
        let targets = selection
        guard !targets.isEmpty else { return }
        performLive(name) {
            for id in targets {
                update(id) { e in
                    body(&e)
                    TextFitter.fit(&e)
                }
            }
            refreshBindings(for: targets)
        }
    }

    // MARK: Insert

    func insertNew(_ list: [Element], files newFiles: [BinaryFile] = [], name: String) {
        guard !list.isEmpty else { return }
        perform(name) {
            for f in newFiles { addFile(f) }
            insert(list)
            selection = Set(list.map(\.id))
        }
    }
}

/// Keeps text element sizes and container heights in sync with their text.
enum TextFitter {
    static func fit(_ e: inout Element) {
        if e.type == .text {
            let size = TextMetrics.measure(e.text, family: e.fontFamily, fontSize: e.fontSize)
            // Keep the anchor implied by the alignment while resizing.
            switch e.textAlign {
            case .left: break
            case .center: e.x += (e.width - size.width) / 2
            case .right: e.x += e.width - size.width
            }
            e.width = size.width
            e.height = size.height
        } else if e.hasLabel {
            let required = TextMetrics.requiredContainerHeight(for: e)
            if e.height < required {
                e.y -= (required - e.height) / 2
                e.height = required
            }
        }
    }
}
