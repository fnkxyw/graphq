import AppKit
import SketchCore
import SketchRender

// MARK: - Hand

@MainActor
final class HandTool: ToolController {
    private unowned let host: CanvasHost
    private var last: CGPoint?

    init(host: CanvasHost) { self.host = host }

    var cursor: NSCursor { last == nil ? .openHand : .closedHand }

    func mouseDown(_ e: PointerEvent) {
        last = e.view
        cursor.set()
    }

    func mouseDragged(_ e: PointerEvent) {
        guard let l = last else { return }
        host.pan(byView: e.view - l)
        last = e.view
    }

    func mouseUp(_ e: PointerEvent) {
        last = nil
        cursor.set()
    }
}

// MARK: - Eraser

/// Marks everything the pointer passes over (whole groups), deletes on mouse up.
@MainActor
final class EraserTool: ToolController {
    private unowned let host: CanvasHost
    private var last: CGPoint?
    private var marked = Set<String>()

    init(host: CanvasHost) { self.host = host }

    var cursor: NSCursor { EraserTool.eraserCursor }

    private static let eraserCursor: NSCursor = {
        let size: CGFloat = 14
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            NSColor.white.withAlphaComponent(0.8).setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.7).setStroke()
            path.lineWidth = 1.2
            path.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()

    func mouseDown(_ e: PointerEvent) {
        last = e.scene
        marked = []
        erase(at: e.scene)
    }

    func mouseDragged(_ e: PointerEvent) {
        // Sample along the segment so fast strokes don't skip thin elements.
        let from = last ?? e.scene
        let steps = max(1, Int(from.distance(to: e.scene) / host.sceneDistance(4)))
        for s in 1...steps { erase(at: from.lerp(to: e.scene, CGFloat(s) / CGFloat(steps))) }
        last = e.scene
    }

    func mouseUp(_ e: PointerEvent) {
        let ids = marked
        marked = []
        host.fadedIds = []
        last = nil
        guard !ids.isEmpty else { return }
        host.store.perform("Erase") { host.store.remove(ids) }
        host.editor.hasInteracted = true
    }

    func cancel() {
        marked = []
        host.fadedIds = []
        host.overlayNeedsDisplay()
    }

    private func erase(at p: CGPoint) {
        guard let hit = host.store.hitTest(p, tolerance: host.sceneDistance(6), includeLocked: false),
              !marked.contains(hit.id) else { return }
        let group = Groups.expand([hit.id], in: host.store.elements, editingGroupId: nil)
        // Erasing a shape also erases its label (labels are part of the element).
        marked.formUnion(group)
        host.fadedIds = marked
    }
}

// MARK: - Text

@MainActor
final class TextTool: ToolController {
    private unowned let host: CanvasHost

    init(host: CanvasHost) { self.host = host }

    var cursor: NSCursor { .iBeam }

    func mouseDown(_ e: PointerEvent) {
        let store = host.store
        // Clicking a container edits its label; clicking text edits that text.
        if let hit = store.hitTest(e.scene, tolerance: host.sceneDistance(4), includeLocked: false)
            ?? store.elements.last(where: { $0.type.isContainer && !$0.locked && HitTest.isInside($0, e.scene) }),
           hit.type == .text || hit.type.isContainer || hit.type.isLinear {
            store.selection = [hit.id]
            host.beginTextEditing(elementId: hit.id, isNew: false)
            return
        }
        TextTool.createText(at: e.scene, host: host)
    }

    func mouseDragged(_ e: PointerEvent) {}
    func mouseUp(_ e: PointerEvent) {}

    /// Creates an empty text element centered vertically on `p` and starts editing it.
    static func createText(at p: CGPoint, host: CanvasHost) {
        var e = host.editor.style.makeElement(.text)
        let size = TextMetrics.measure(" ", family: e.fontFamily, fontSize: e.fontSize)
        e.x = p.x
        e.y = p.y - size.height / 2
        e.width = 1
        e.height = size.height
        host.store.beginInteraction()
        host.store.insert(e)
        host.store.selection = [e.id]
        host.beginTextEditing(elementId: e.id, isNew: true)
    }
}

// MARK: - Freedraw

@MainActor
final class FreedrawTool: ToolController {
    private unowned let host: CanvasHost
    private var elementId: String?
    private var points: [CGPoint] = []
    private var pressures: [Double] = []

    init(host: CanvasHost) { self.host = host }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ e: PointerEvent) {
        var el = host.editor.style.makeElement(.freedraw)
        el.simulatePressure = e.pressure == nil
        points = [e.scene]
        pressures = [e.pressure ?? 0.5]
        el.setAbsolutePoints(points)
        el.pressures = el.simulatePressure ? [] : pressures
        host.store.beginInteraction()
        host.store.insert(el)
        elementId = el.id
    }

    func mouseDragged(_ e: PointerEvent) {
        guard let id = elementId, let last = points.last else { return }
        if last.distance(to: e.scene) < host.sceneDistance(1) { return }
        points.append(e.scene)
        pressures.append(e.pressure ?? 0.5)
        let pts = points, prs = pressures
        host.store.update(id) { el in
            el.setAbsolutePoints(pts)
            if !el.simulatePressure { el.pressures = prs }
        }
    }

    func mouseUp(_ e: PointerEvent) {
        guard elementId != nil else { return }
        host.store.endInteraction("Draw")
        elementId = nil
        points = []
        pressures = []
        host.editor.finishedCreating()
    }

    func cancel() {
        if elementId != nil { host.store.cancelInteraction() }
        elementId = nil
    }
}

// MARK: - Rectangle / ellipse / diamond

@MainActor
final class ShapeTool: ToolController {
    private unowned let host: CanvasHost
    private let type: ElementType
    private var start: CGPoint?
    private var elementId: String?

    init(host: CanvasHost, type: ElementType) {
        self.host = host
        self.type = type
    }

    func mouseDown(_ e: PointerEvent) {
        let p = host.snap(point: e.scene, excluding: [])
        start = p
        var el = host.editor.style.makeElement(type)
        el.x = p.x
        el.y = p.y
        host.store.beginInteraction()
        host.store.insert(el)
        elementId = el.id
        host.store.selection = []
    }

    func mouseDragged(_ e: PointerEvent) {
        guard let start, let id = elementId else { return }
        var p = host.snap(point: e.scene, excluding: [id])
        if e.shift {
            // Square / circle.
            let d = max(abs(p.x - start.x), abs(p.y - start.y))
            p = CGPoint(x: start.x + (p.x >= start.x ? d : -d), y: start.y + (p.y >= start.y ? d : -d))
        }
        var rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        if e.option {
            // Draw from center.
            rect = CGRect(x: start.x - abs(p.x - start.x), y: start.y - abs(p.y - start.y),
                          width: abs(p.x - start.x) * 2, height: abs(p.y - start.y) * 2)
        }
        host.store.update(id) { el in
            el.x = rect.minX; el.y = rect.minY
            el.width = rect.width; el.height = rect.height
        }
    }

    func mouseUp(_ e: PointerEvent) {
        guard let id = elementId else { return }
        host.clearGuides()
        elementId = nil
        start = nil
        if let el = host.store.element(id), el.width < 2 || el.height < 2 {
            // A click without a drag: no zero-size shapes.
            host.store.cancelInteraction()
            return
        }
        host.store.selection = [id]
        host.store.endInteraction("Draw \(type.rawValue.capitalized)")
        host.editor.finishedCreating()
    }

    func cancel() {
        if elementId != nil { host.store.cancelInteraction() }
        elementId = nil
        host.clearGuides()
    }
}
