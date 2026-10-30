import AppKit
import SketchCore

/// Select / move / resize / rotate / marquee / edit points of linear elements.
@MainActor
final class SelectionTool: ToolController {
    private enum State {
        case idle
        /// Mouse is down; becomes a move once the pointer travels far enough.
        case pending(down: PointerEvent, hitId: String?)
        case moving(start: CGPoint, originals: [Element])
        case resizing(handle: ResizeHandle, originals: [Element], frame: SelectionFrame)
        case rotating(center: CGPoint, startAngle: CGFloat, originals: [Element])
        case marquee(start: CGPoint, current: CGPoint, base: Set<String>)
        case pointDrag(id: String, index: Int, original: Element)
    }

    private unowned let host: CanvasHost
    private var state: State = .idle
    private var hoverCursor: NSCursor = .arrow

    init(host: CanvasHost) { self.host = host }

    private var store: SceneStore { host.store }
    private var zoom: CGFloat { host.viewport.zoom }

    var cursor: NSCursor {
        switch state {
        case .moving: .closedHand
        default: hoverCursor
        }
    }

    // MARK: Mouse down

    func mouseDown(_ e: PointerEvent) {
        let tol = host.sceneDistance(6)

        // 1. Point handles of a single selected linear element.
        if let linear = singleEditableLinear() {
            let pts = linear.absolutePoints
            if let i = pts.firstIndex(where: { $0.distance(to: e.scene) <= host.sceneDistance(7) }) {
                if e.clickCount == 2 && pts.count > 2 {
                    // Double-click a point to remove it.
                    store.perform("Delete Point") {
                        var p = pts
                        p.remove(at: i)
                        store.update(linear.id) { $0.setAbsolutePoints(p) }
                        if i == 0 { store.setBinding(nil, end: .start, arrowId: linear.id) }
                        if i == pts.count - 1 { store.setBinding(nil, end: .end, arrowId: linear.id) }
                    }
                    return
                }
                store.beginInteraction()
                state = .pointDrag(id: linear.id, index: i, original: linear)
                return
            }
            // Midpoint handles insert a new point (this is how arrows get bent).
            for i in 0..<(pts.count - 1) {
                let mid = midpoint(of: linear, segment: i)
                if mid.distance(to: e.scene) <= host.sceneDistance(7) {
                    store.beginInteraction()
                    var p = pts
                    p.insert(mid, at: i + 1)
                    store.update(linear.id) { $0.setAbsolutePoints(p) }
                    if let updated = store.element(linear.id) {
                        state = .pointDrag(id: linear.id, index: i + 1, original: updated)
                    }
                    return
                }
            }
        }

        // 2. Resize / rotate handles.
        if let frame = SelectionFrame.make(for: store), frame.showsHandles, !e.shift {
            if let r = frame.rotationHandle(zoom: zoom), r.distance(to: e.scene) <= host.sceneDistance(8) {
                store.beginInteraction()
                let c = frame.center
                state = .rotating(center: c, startAngle: atan2(e.scene.y - c.y, e.scene.x - c.x),
                                  originals: store.selectedElements)
                return
            }
            for (h, p) in frame.handles(zoom: zoom) where p.distance(to: e.scene) <= host.sceneDistance(7) {
                store.beginInteraction()
                state = .resizing(handle: h, originals: store.selectedElements, frame: frame)
                return
            }
        }

        // 3. Elements.
        let hit = store.hitTest(e.scene, tolerance: tol)
        if e.clickCount == 2 {
            handleDoubleClick(hit, at: e.scene)
            state = .idle
            return
        }
        if let hit {
            if e.shift {
                let unit = Groups.expand([hit.id], in: store.elements, editingGroupId: store.editingGroupId)
                if store.selection.isSuperset(of: unit) {
                    store.selection.subtract(unit)
                } else {
                    store.selection.formUnion(unit)
                }
            } else if !store.selection.contains(hit.id) {
                if let g = store.editingGroupId, !hit.groupIds.contains(g) { store.editingGroupId = nil }
                store.select([hit.id])
            }
            state = .pending(down: e, hitId: hit.id)
            return
        }
        // Dragging inside the selection box moves the selection even between shapes.
        if !e.shift, store.selection.count > 1, store.selectionBounds.contains(e.scene) {
            state = .pending(down: e, hitId: nil)
            return
        }
        if !e.shift { store.clearSelection() }
        state = .marquee(start: e.scene, current: e.scene, base: store.selection)
    }

    private func handleDoubleClick(_ hit: Element?, at p: CGPoint) {
        guard let hit else {
            store.clearSelection()
            TextTool.createText(at: p, host: host)
            return
        }
        if hit.locked { return }
        // Enter a group: the next level becomes selectable individually.
        if let g = Groups.selectionGroup(of: hit, editingGroupId: store.editingGroupId), store.selection.count > 1 {
            store.editingGroupId = g
            store.selection = Groups.expand([hit.id], in: store.elements, editingGroupId: g)
            if store.selection.count > 1 { return }
        }
        if hit.type == .text || hit.type.isContainer {
            store.selection = [hit.id]
            host.beginTextEditing(elementId: hit.id, isNew: false)
        }
    }

    // MARK: Drag

    func mouseDragged(_ e: PointerEvent) {
        switch state {
        case .idle:
            break
        case .pending(let down, _):
            guard down.view.distance(to: e.view) > 3 else { return }
            startMove(from: down, option: e.option)
            mouseDragged(e)
        case .moving(let start, let originals):
            drag(originals: originals, start: start, e: e)
        case .resizing(let handle, let originals, let frame):
            resize(handle: handle, originals: originals, frame: frame, e: e)
        case .rotating(let center, let startAngle, let originals):
            var delta = atan2(e.scene.y - center.y, e.scene.x - center.x) - startAngle
            if e.shift, let first = originals.first {
                // Snap the resulting angle to 15° steps.
                let step = CGFloat.pi / 12
                let target = ((first.angle + delta) / step).rounded() * step
                delta = target - first.angle
            }
            for n in Transforms.rotate(originals, around: center, by: delta) { store.replace(n) }
            store.refreshBindings(for: Set(originals.map(\.id)))
        case .marquee(let start, _, let base):
            state = .marquee(start: start, current: e.scene, base: base)
            let rect = CGRect(x: min(start.x, e.scene.x), y: min(start.y, e.scene.y),
                              width: abs(e.scene.x - start.x), height: abs(e.scene.y - start.y))
            let enclosed = store.elements(in: rect)
                .filter { !$0.locked && HitTest.isEnclosed($0, by: rect) }
                .map(\.id)
            store.selection = base.union(Groups.expand(Set(enclosed), in: store.elements, editingGroupId: store.editingGroupId))
            host.overlayNeedsDisplay()
        case .pointDrag(let id, let index, let original):
            dragPoint(id: id, index: index, original: original, e: e)
        }
    }

    private func startMove(from down: PointerEvent, option: Bool) {
        let movable = store.selectedElements.filter { !$0.locked }
        guard !movable.isEmpty else { state = .idle; return }
        store.beginInteraction()
        var originals = movable
        if option {
            // Option-drag leaves the originals in place and moves copies.
            store.selection = Set(movable.map(\.id))
            originals = store.duplicateSelectionInPlace()
        }
        store.detachArrows(movedIds: Set(originals.map(\.id)))
        originals = originals.compactMap { store.element($0.id) }
        state = .moving(start: down.scene, originals: originals)
        hoverCursor = .closedHand
    }

    private func drag(originals: [Element], start: CGPoint, e: PointerEvent) {
        var delta = e.scene - start
        if e.shift {
            // Constrain to the dominant axis.
            if abs(delta.x) > abs(delta.y) { delta.y = 0 } else { delta.x = 0 }
        }
        let ids = Set(originals.map(\.id))
        let box = SceneGeometry.bounds(of: originals).offsetBy(dx: delta.x, dy: delta.y)
        if store.settings.gridEnabled {
            let snapped = Snapping.snapToGrid(box.origin)
            delta = delta + (snapped - box.origin)
        } else if host.editor.snapToObjects && !e.command {
            delta = delta + host.snapOffset(for: box, excluding: ids)
        }
        for o in originals {
            var m = o
            m.move(by: delta)
            store.replace(m)
        }
        store.refreshBindings(for: ids)
    }

    private func resize(handle: ResizeHandle, originals: [Element], frame: SelectionFrame, e: PointerEvent) {
        var pointer = e.scene
        let ids = Set(originals.map(\.id))
        if frame.angle == 0 {
            pointer = host.snap(point: pointer, excluding: ids)
        }
        let updated: [Element]
        if let single = frame.single, originals.count == 1 {
            // Images keep their aspect ratio unless Shift is held.
            let keep = single.type == .image ? !e.shift : e.shift
            updated = [Transforms.resize(single, handle: handle, pointer: pointer, keepAspect: keep, fromCenter: e.option)]
        } else {
            updated = Transforms.resize(originals, bounds: frame.rect, handle: handle, pointer: pointer,
                                        keepAspect: e.shift, fromCenter: e.option)
        }
        for n in updated { store.replace(n) }
        store.refreshBindings(for: ids)
    }

    private func dragPoint(id: String, index: Int, original: Element, e: PointerEvent) {
        var pts = original.absolutePoints
        guard index < pts.count else { return }
        var p = host.snap(point: e.scene, excluding: [id])
        if e.shift, pts.count > 1 {
            let anchor = pts[index == 0 ? 1 : index - 1]
            let d = p - anchor
            let step = CGFloat.pi / 12
            let a = (atan2(d.y, d.x) / step).rounded() * step
            p = anchor + CGPoint(x: cos(a) * d.length, y: sin(a) * d.length)
        }
        pts[index] = p
        let isEnd = index == 0 || index == pts.count - 1
        var el = store.element(id) ?? original
        el.setAbsolutePoints(pts)
        if isEnd && original.type.isLinear {
            let target = ArrowBinding.target(at: p, in: store.elements, excluding: [id], threshold: host.sceneDistance(4))
            host.bindingHighlight = target?.id
            let binding = target.map { ArrowBinding.makeBinding(to: $0, at: p) }
            if index == 0 { el.startBinding = binding } else { el.endBinding = binding }
        }
        ArrowBinding.updateEndpoints(of: &el) { store.element($0) }
        store.replace(el)
    }

    // MARK: Mouse up

    func mouseUp(_ e: PointerEvent) {
        switch state {
        case .pending(let down, let hitId):
            // Plain click on an element of a larger selection narrows the selection to it.
            if !down.shift, let hitId, store.selection.contains(hitId) {
                let unit = Groups.expand([hitId], in: store.elements, editingGroupId: store.editingGroupId)
                if unit != store.selection { store.selection = unit }
            }
        case .moving:
            store.endInteraction("Move")
            hoverCursor = .arrow
        case .resizing:
            store.endInteraction("Resize")
        case .rotating:
            store.endInteraction("Rotate")
        case .marquee:
            host.overlayNeedsDisplay()
        case .pointDrag(let id, let index, _):
            commitPointDrag(id: id, index: index)
        case .idle:
            break
        }
        state = .idle
        host.clearGuides()
        host.bindingHighlight = nil
        host.editor.hasInteracted = true
    }

    private func commitPointDrag(id: String, index: Int) {
        guard let el = store.element(id) else { store.endInteraction("Edit Points"); return }
        let count = el.points.count
        if el.type.isLinear && (index == 0 || index == count - 1) {
            let end: LinearEnd = index == 0 ? .start : .end
            let binding = end == .start ? el.startBinding : el.endBinding
            // Clear the preview, then bind properly so the target's back-reference is kept in sync.
            store.update(id) { if end == .start { $0.startBinding = nil } else { $0.endBinding = nil } }
            store.setBinding(binding, end: end, arrowId: id)
        }
        store.endInteraction("Edit Points")
    }

    func mouseMoved(_ e: PointerEvent) {
        hoverCursor = cursorForHover(e.scene)
        hoverCursor.set()
    }

    func cancel() {
        switch state {
        case .moving, .resizing, .rotating, .pointDrag: store.cancelInteraction()
        default: break
        }
        state = .idle
        host.clearGuides()
        host.bindingHighlight = nil
    }

    // MARK: Overlay

    func drawOverlay(in ctx: CGContext, zoom: CGFloat) {
        guard case .marquee(let start, let current, _) = state else { return }
        let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        let accent = NSColor.controlAccentColor
        ctx.setFillColor(accent.withAlphaComponent(0.08).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(accent.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1 / zoom)
        ctx.stroke(rect)
    }

    // MARK: Helpers

    private func singleEditableLinear() -> Element? {
        guard store.selection.count == 1, let id = store.selection.first,
              let e = store.element(id), e.type.isLinear, !e.locked else { return nil }
        return e
    }

    /// Midpoint handle of segment `i` (on the curve for curved elements).
    func midpoint(of e: Element, segment i: Int) -> CGPoint {
        if e.curved && e.points.count > 2 {
            let beziers = Curves.catmullRom(e.points)
            if i < beziers.count { return e.toScene(beziers[i].point(at: 0.5)) }
        }
        let pts = e.absolutePoints
        return pts[i].lerp(to: pts[i + 1], 0.5)
    }

    private func cursorForHover(_ p: CGPoint) -> NSCursor {
        if let linear = singleEditableLinear() {
            if linear.absolutePoints.contains(where: { $0.distance(to: p) <= host.sceneDistance(7) }) { return .pointingHand }
        }
        if let frame = SelectionFrame.make(for: store), frame.showsHandles {
            if let r = frame.rotationHandle(zoom: zoom), r.distance(to: p) <= host.sceneDistance(8) { return .pointingHand }
            for (h, hp) in frame.handles(zoom: zoom) where hp.distance(to: p) <= host.sceneDistance(7) {
                return Cursors.resize(for: h, angle: frame.angle)
            }
        }
        if let hit = store.hitTest(p, tolerance: host.sceneDistance(6)), !hit.locked { return .openHand }
        return .arrow
    }
}

enum Cursors {
    /// Diagonal/straight resize cursor matching the handle direction after rotation.
    static func resize(for handle: ResizeHandle, angle: CGFloat) -> NSCursor {
        let f = handle.factor
        var a = atan2(f.y - 0.5, f.x - 0.5) + angle
        a = Transforms.normalizeAngle(a)
        let octant = Int((a / (.pi / 4)).rounded()) % 4
        switch octant {
        case 0: return .resizeLeftRight
        case 2: return .resizeUpDown
        case 1: return diagonal(nwse: true)
        default: return diagonal(nwse: false)
        }
    }

    private static func diagonal(nwse: Bool) -> NSCursor {
        // macOS 15+ ships frame-resize cursors; fall back to crosshair on 14.
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: nwse ? .topLeft : .topRight, directions: .all)
        }
        return .crosshair
    }
}
