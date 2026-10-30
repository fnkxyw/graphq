import AppKit
import SketchCore
import SketchRender

/// The infinite canvas. Owns the viewport, routes input to the active tool and
/// draws the scene with dirty-rect invalidation and viewport culling.
@MainActor
final class CanvasView: NSView, CanvasHost {
    let store: SceneStore
    let editor: Editor
    let renderer = ElementRenderer()

    private(set) var viewport = Viewport() {
        didSet {
            if viewport != oldValue {
                needsDisplay = true
                if editor.zoom != viewport.zoom { editor.zoom = viewport.zoom }
                textEditor?.layout()
            }
        }
    }
    private var didInitialLayout = false

    var tool: ToolController!
    var textEditor: TextEditingController?

    // Input state
    var spacePanning = false
    var panLast: CGPoint?
    var lastMouseView: CGPoint?

    // Overlay state
    var snapGuides: [SnapGuide] = [] {
        didSet { invalidateGuides(oldValue); invalidateGuides(snapGuides) }
    }
    var bindingHighlight: String? {
        didSet {
            guard bindingHighlight != oldValue else { return }
            for id in [oldValue, bindingHighlight].compactMap({ $0 }) {
                if let e = store.element(id) { invalidateScene(e.aabb) }
            }
        }
    }
    var fadedIds: Set<String> = [] {
        didSet {
            for id in fadedIds.symmetricDifference(oldValue) {
                if let e = store.element(id) { invalidateScene(e.aabb) }
            }
        }
    }

    init(editor: Editor) {
        self.editor = editor
        self.store = editor.store
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        tool = ToolFactory.make(editor.tool, host: self)
        registerForDraggedTypes([.fileURL, .png, .tiff, SceneClipboard.elementsType])

        store.onInvalidate = { [weak self] rect in
            guard let self else { return }
            if let rect { self.invalidateScene(rect) } else { self.needsDisplay = true }
        }
        store.onSelectionChange = { [weak self] in self?.needsDisplay = true }
        editor.canvas = self
        updateTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
    }

    override func layout() {
        super.layout()
        if !didInitialLayout, bounds.width > 0 {
            didInitialLayout = true
            if store.elements.isEmpty {
                viewport.origin = CGPoint(x: -bounds.width / 2, y: -bounds.height / 2)
            } else {
                viewport.fit(SceneGeometry.bounds(of: store.elements), in: bounds.size)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor.set()
    }

    var currentCursor: NSCursor {
        if spacePanning { return panLast == nil ? .openHand : .closedHand }
        return tool.cursor
    }

    // MARK: Theme

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTheme()
    }

    var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private func updateTheme() {
        renderer.theme = RenderTheme(isDark: isDark)
        needsDisplay = true
        textEditor?.layout()
    }

    // MARK: Tools

    func toolDidChange() {
        if textEditor != nil { endTextEditing() }
        tool.cancel()
        tool = ToolFactory.make(editor.tool, host: self)
        if editor.tool != .selection && editor.tool != .hand { store.editingGroupId = nil }
        window?.invalidateCursorRects(for: self)
        currentCursor.set()
        needsDisplay = true
    }

    // MARK: Invalidation

    func invalidateScene(_ rect: CGRect) {
        guard !rect.isNull else { return }
        // Pad in screen space too, for selection handles and the rotation knob.
        let r = viewport.toView(rect).insetBy(dx: -36, dy: -36)
        setNeedsDisplay(r.intersection(bounds))
    }

    private func invalidateGuides(_ guides: [SnapGuide]) {
        for g in guides { invalidateScene(CGRect(enclosing: [g.from, g.to])) }
    }

    func overlayNeedsDisplay() { needsDisplay = true }

    // MARK: CanvasHost

    func sceneDistance(_ px: CGFloat) -> CGFloat { px / viewport.zoom }

    private func snapReferences(excluding: Set<String>) -> [CGRect] {
        let visible = viewport.toScene(bounds)
        return store.elements(in: visible)
            .filter { !excluding.contains($0.id) }
            .prefix(400)
            .map(\.aabb)
    }

    func snap(point p: CGPoint, excluding: Set<String>) -> CGPoint {
        if store.settings.gridEnabled { return Snapping.snapToGrid(p) }
        guard editor.snapToObjects, !NSEvent.modifierFlags.contains(.command) else {
            clearGuides()
            return p
        }
        let r = Snapping.snap(point: p, to: snapReferences(excluding: excluding), threshold: sceneDistance(6))
        snapGuides = r.guides
        return p + r.offset
    }

    func snapOffset(for box: CGRect, excluding: Set<String>) -> CGPoint {
        let r = Snapping.snap(box, to: snapReferences(excluding: excluding), threshold: sceneDistance(6))
        snapGuides = r.guides
        return r.offset
    }

    func clearGuides() {
        if !snapGuides.isEmpty { snapGuides = [] }
    }

    func pan(byView delta: CGPoint) {
        viewport.pan(byView: delta)
    }

    // MARK: Viewport commands

    func setZoom(_ z: CGFloat, anchor: CGPoint? = nil) {
        var v = viewport
        v.zoom(to: z, anchor: anchor ?? CGPoint(x: bounds.midX, y: bounds.midY))
        viewport = v
    }

    /// Steps through "nice" zoom levels.
    func zoomStep(in zoomIn: Bool) {
        let levels: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.25, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 30]
        let z = viewport.zoom
        let next = zoomIn ? levels.first { $0 > z + 0.001 } ?? Viewport.maxZoom
                          : levels.last { $0 < z - 0.001 } ?? Viewport.minZoom
        setZoom(next)
    }

    func zoomToFit(selectionOnly: Bool) {
        let list = selectionOnly && !store.selection.isEmpty ? store.selectedElements : store.elements
        guard !list.isEmpty else { setZoom(1); return }
        var v = viewport
        v.fit(SceneGeometry.bounds(of: list), in: bounds.size, maxFitZoom: selectionOnly ? 4 : 1)
        viewport = v
    }

    /// Scene point at the view center.
    var sceneCenter: CGPoint { viewport.toScene(CGPoint(x: bounds.midX, y: bounds.midY)) }

    /// Where pasted content should go: the pointer if it is over the canvas, else the center.
    var pasteTarget: CGPoint {
        if let m = lastMouseView, bounds.contains(m) { return viewport.toScene(m) }
        return sceneCenter
    }
}
