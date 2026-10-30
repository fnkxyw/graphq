import AppKit
import SketchCore

/// Arrow / line creation.
/// - Drag: two-point element.
/// - Click: starts a polyline; each click adds a point, the last point follows the pointer.
///   Enter, Escape, a double-click or clicking the last point finishes it.
/// Endpoints dropped on (or near) a shape bind to it.
@MainActor
final class LinearTool: ToolController {
    private enum State {
        case idle
        case dragging(id: String, points: [CGPoint], downView: CGPoint)
        case polyline(id: String, points: [CGPoint])
    }

    private unowned let host: CanvasHost
    private let type: ElementType
    private var state: State = .idle

    init(host: CanvasHost, type: ElementType) {
        self.host = host
        self.type = type
    }

    func mouseDown(_ e: PointerEvent) {
        let p = host.snap(point: e.scene, excluding: currentId.map { [$0] } ?? [])
        switch state {
        case .polyline(let id, var pts):
            let lastFixed = pts[pts.count - 2]
            if e.clickCount >= 2 || lastFixed.distance(to: p) < host.sceneDistance(6) {
                finish(id: id, points: Array(pts.dropLast()))
                return
            }
            if type == .line, pts.count > 2, pts[0].distance(to: p) < host.sceneDistance(8) {
                // Clicking the first point closes the shape.
                pts[pts.count - 1] = pts[0]
                finish(id: id, points: pts)
                return
            }
            pts[pts.count - 1] = constrained(p, shift: e.shift, from: lastFixed)
            pts.append(pts[pts.count - 1])
            state = .polyline(id: id, points: pts)
            apply(id: id, points: pts)
        case .idle, .dragging:
            var el = host.editor.style.makeElement(type)
            el.setAbsolutePoints([p, p])
            host.store.beginInteraction()
            host.store.insert(el)
            host.store.selection = []
            if let target = ArrowBinding.target(at: p, in: host.store.elements, excluding: [el.id],
                                                threshold: host.sceneDistance(4)) {
                host.store.setBinding(ArrowBinding.makeBinding(to: target, at: p), end: .start, arrowId: el.id)
            }
            state = .dragging(id: el.id, points: [p, p], downView: e.view)
        }
    }

    func mouseDragged(_ e: PointerEvent) {
        guard case .dragging(let id, var pts, let down) = state else { return }
        let p = host.snap(point: e.scene, excluding: [id])
        pts[1] = constrained(p, shift: e.shift, from: pts[0])
        state = .dragging(id: id, points: pts, downView: down)
        apply(id: id, points: pts)
    }

    func mouseUp(_ e: PointerEvent) {
        guard case .dragging(let id, let pts, let down) = state else { return }
        if down.distance(to: e.view) < 4 {
            // Click without drag: switch to click-to-add-points mode.
            state = .polyline(id: id, points: [pts[0], pts[0]])
            return
        }
        finish(id: id, points: pts)
    }

    func mouseMoved(_ e: PointerEvent) {
        guard case .polyline(let id, var pts) = state else { return }
        let p = host.snap(point: e.scene, excluding: [id])
        pts[pts.count - 1] = constrained(p, shift: e.shift, from: pts[pts.count - 2])
        state = .polyline(id: id, points: pts)
        apply(id: id, points: pts)
    }

    func keyDown(_ event: NSEvent) -> Bool {
        guard case .polyline(let id, let pts) = state else { return false }
        if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 53 { // return, enter, escape
            finish(id: id, points: Array(pts.dropLast()))
            return true
        }
        return false
    }

    func cancel() {
        switch state {
        case .polyline(let id, let pts): finish(id: id, points: Array(pts.dropLast()))
        case .dragging: host.store.cancelInteraction()
        case .idle: break
        }
        state = .idle
        host.bindingHighlight = nil
        host.clearGuides()
    }

    var cursor: NSCursor { .crosshair }

    // MARK: Helpers

    private var currentId: String? {
        switch state {
        case .dragging(let id, _, _), .polyline(let id, _): id
        case .idle: nil
        }
    }

    /// Shift snaps the segment angle to 15° steps.
    private func constrained(_ p: CGPoint, shift: Bool, from origin: CGPoint) -> CGPoint {
        guard shift else { return p }
        let d = p - origin
        let step = CGFloat.pi / 12
        let angle = (atan2(d.y, d.x) / step).rounded() * step
        let len = d.length
        return origin + CGPoint(x: cos(angle) * len, y: sin(angle) * len)
    }

    /// Writes points into the element, previewing the end binding.
    private func apply(id: String, points: [CGPoint]) {
        let store = host.store
        guard var el = store.element(id), let end = points.last else { return }
        el.setAbsolutePoints(points)
        let target = ArrowBinding.target(at: end, in: store.elements, excluding: [id], threshold: host.sceneDistance(4))
        host.bindingHighlight = target?.id
        el.endBinding = target.map { ArrowBinding.makeBinding(to: $0, at: end) }
        ArrowBinding.updateEndpoints(of: &el) { store.element($0) }
        // The preview binding is not committed to the target yet.
        if target == nil { el.endBinding = nil }
        store.replace(el)
    }

    private func finish(id: String, points: [CGPoint]) {
        state = .idle
        host.bindingHighlight = nil
        host.clearGuides()
        let store = host.store
        let length = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard points.count >= 2, length > host.sceneDistance(3) else {
            store.cancelInteraction()
            return
        }
        guard var el = store.element(id) else { store.cancelInteraction(); return }
        el.endBinding = nil
        el.setAbsolutePoints(points)
        store.replace(el)
        if let end = points.last,
           let target = ArrowBinding.target(at: end, in: store.elements, excluding: [id], threshold: host.sceneDistance(4)) {
            store.setBinding(ArrowBinding.makeBinding(to: target, at: end), end: .end, arrowId: id)
        }
        if let bound = store.element(id), bound.startBinding != nil || bound.endBinding != nil {
            store.update(id) { ArrowBinding.updateEndpoints(of: &$0) { store.element($0) } }
        }
        store.selection = [id]
        store.endInteraction(type == .arrow ? "Draw Arrow" : "Draw Line")
        host.editor.finishedCreating()
    }
}
