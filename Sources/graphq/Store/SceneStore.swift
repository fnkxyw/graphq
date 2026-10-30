import CoreGraphics
import Foundation
import Observation
import SketchCore

/// Owns the document content (elements in z-order, files), the selection and the history.
///
/// Mutations come in two flavors:
/// - `perform(_:_:)` — a discrete action, recorded as one undo step;
/// - `beginInteraction()` / live mutators / `endInteraction(_:)` — drags and other
///   continuous edits, recorded as one undo step when the gesture ends.
/// History is snapshot-based: arrays of value-type elements are copy-on-write,
/// so a snapshot is cheap and undo can never get out of sync with the model.
@MainActor
@Observable
final class SceneStore {
    struct Snapshot: Sendable, Equatable {
        var elements: [Element]
        var files: [String: BinaryFile]
        var selection: Set<String>
    }

    // MARK: Content (not observed: changes every frame during drags; the canvas listens via `onInvalidate`)

    @ObservationIgnored private(set) var elements: [Element] = []
    @ObservationIgnored private(set) var indexById: [String: Int] = [:]
    @ObservationIgnored private(set) var spatial = SpatialIndex()
    @ObservationIgnored private(set) var files: [String: BinaryFile] = [:]

    // MARK: Observed state

    var settings: SceneSettings
    var selection: Set<String> = [] {
        didSet { if selection != oldValue { onSelectionChange?() } }
    }
    /// Group the user has "entered" by double-clicking; selection works inside it.
    var editingGroupId: String?
    /// Bumped whenever committed content changes. SwiftUI views read this
    /// instead of `elements` so they refresh once per action, not once per frame.
    private(set) var revision = 0
    var isEmpty: Bool { _ = revision; return elements.isEmpty }

    // MARK: Plumbing

    @ObservationIgnored weak var undoManager: UndoManager?
    /// Scene-space rect that needs redrawing; `nil` means everything.
    @ObservationIgnored var onInvalidate: ((CGRect?) -> Void)?
    @ObservationIgnored var onSelectionChange: (() -> Void)?
    /// Receives the committed content after every undoable change (used by the document for saving).
    @ObservationIgnored var onCommit: ((SceneData) -> Void)?
    @ObservationIgnored private var interactionSnapshot: Snapshot?
    /// Pending commit for continuous style edits (color picker, sliders).
    @ObservationIgnored private var liveCommit: (name: String, task: Task<Void, Never>)?

    init(data: SceneData) {
        self.settings = data.settings
        self.elements = data.elements
        self.files = data.files
        var index: [String: Int] = [:]
        var spatial = SpatialIndex()
        for (i, e) in data.elements.enumerated() {
            index[e.id] = i
            spatial.insert(e.id, rect: e.aabb)
        }
        self.indexById = index
        self.spatial = spatial
    }

    var sceneData: SceneData { SceneData(elements: elements, files: files, settings: settings) }

    // MARK: Lookup

    func element(_ id: String) -> Element? { indexById[id].map { elements[$0] } }

    var selectedElements: [Element] {
        _ = revision
        return elements.filter { selection.contains($0.id) }
    }

    /// Element ids intersecting a scene rect, back-to-front.
    func elements(in rect: CGRect) -> [Element] {
        let ids = spatial.query(rect)
        return ids.compactMap { indexById[$0] }.sorted().map { elements[$0] }
    }

    /// Topmost element hit at `p`.
    func hitTest(_ p: CGPoint, tolerance: CGFloat, includeLocked: Bool = true) -> Element? {
        let candidates = spatial.query(point: p, radius: tolerance + 20)
            .compactMap { indexById[$0] }
            .sorted(by: >)
        for i in candidates {
            let e = elements[i]
            if !includeLocked && e.locked { continue }
            if HitTest.hits(e, p, tolerance: tolerance) { return e }
        }
        return nil
    }

    // MARK: History

    func snapshot() -> Snapshot { Snapshot(elements: elements, files: files, selection: selection) }

    /// Runs `body` and records it as one undoable action named `name`.
    func perform(_ name: String, _ body: () -> Void) {
        flushLiveEdits()
        if interactionSnapshot != nil {
            body()
            return
        }
        let before = snapshot()
        body()
        commit(from: before, name: name)
    }

    func beginInteraction() {
        flushLiveEdits()
        if interactionSnapshot == nil { interactionSnapshot = snapshot() }
    }

    /// Continuous edits (e.g. dragging in the color panel) are applied immediately and
    /// committed as a single undo step once they pause.
    func performLive(_ name: String, _ body: () -> Void) {
        if liveCommit == nil {
            flushLiveEdits()
            if interactionSnapshot == nil { interactionSnapshot = snapshot() }
        }
        liveCommit?.task.cancel()
        body()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flushLiveEdits()
        }
        liveCommit = (name, task)
    }

    func flushLiveEdits() {
        guard let live = liveCommit else { return }
        liveCommit = nil
        live.task.cancel()
        endInteraction(live.name)
    }

    var isInteracting: Bool { interactionSnapshot != nil }

    func endInteraction(_ name: String) {
        guard let before = interactionSnapshot else { return }
        interactionSnapshot = nil
        commit(from: before, name: name)
    }

    /// Reverts everything since `beginInteraction()` without touching history.
    func cancelInteraction() {
        guard let before = interactionSnapshot else { return }
        interactionSnapshot = nil
        apply(before)
    }

    private func commit(from before: Snapshot, name: String) {
        guard before.elements != elements || before.files != files else {
            revision += 1
            return
        }
        registerUndo(restoring: before, redo: snapshot(), name: name)
        revision += 1
        onCommit?(sceneData)
    }

    private func registerUndo(restoring target: Snapshot, redo: Snapshot, name: String) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { store in
            store.apply(target)
            store.registerUndo(restoring: redo, redo: target, name: name)
            store.revision += 1
            store.onCommit?(store.sceneData)
        }
        um.setActionName(name)
    }

    private func apply(_ s: Snapshot) {
        elements = s.elements
        files = s.files
        let ids = Set(s.elements.map(\.id))
        selection = s.selection.intersection(ids)
        rebuildIndex()
        onInvalidate?(nil)
    }

    private func rebuildIndex() {
        indexById.removeAll(keepingCapacity: true)
        spatial.removeAll()
        for (i, e) in elements.enumerated() {
            indexById[e.id] = i
            spatial.insert(e.id, rect: e.aabb)
        }
    }

    // MARK: Low-level mutators (callers wrap them in perform / interactions)

    /// Mutates one element in place; bumps its version and invalidates old + new bounds.
    func update(_ id: String, _ body: (inout Element) -> Void) {
        guard let i = indexById[id] else { return }
        let old = elements[i]
        var e = old
        body(&e)
        guard e != old else { return }
        e.bump(comparedTo: old)
        elements[i] = e
        spatial.insert(id, rect: e.aabb)
        invalidate(old.aabb.union(e.aabb), strokeWidth: max(old.strokeWidth, e.strokeWidth))
    }

    /// Replaces an element wholesale (used by tools that compute from an original).
    func replace(_ e: Element) {
        update(e.id) { $0 = e }
    }

    func insert(_ e: Element, at position: Int? = nil) {
        let pos = min(position ?? elements.count, elements.count)
        elements.insert(e, at: pos)
        if pos == elements.count - 1 {
            indexById[e.id] = pos
            spatial.insert(e.id, rect: e.aabb)
        } else {
            rebuildIndex()
        }
        invalidate(e.aabb, strokeWidth: e.strokeWidth)
    }

    func insert(_ list: [Element]) {
        for e in list { insert(e) }
    }

    func remove(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let removed = elements.filter { ids.contains($0.id) }
        elements.removeAll { ids.contains($0.id) }
        ArrowBinding.cleanup(in: &elements)
        rebuildIndex()
        selection.subtract(ids)
        invalidate(SceneGeometry.bounds(of: removed), strokeWidth: 8)
        // Bindings cleanup may have touched other elements; redraw all to be safe.
        onInvalidate?(nil)
    }

    /// Applies a new z-order (must be a permutation of the current elements).
    func reorder(_ newOrder: [Element]) {
        elements = newOrder
        rebuildIndex()
        onInvalidate?(nil)
    }

    func addFile(_ file: BinaryFile) {
        files[file.id] = file
    }

    func setGridEnabled(_ on: Bool) {
        settings.gridEnabled = on
        onInvalidate?(nil)
        onCommit?(sceneData)
    }

    /// Re-aims arrows bound to the given elements.
    func refreshBindings(for ids: Set<String>) {
        let before = ids.compactMap { indexById[$0] }.flatMap { elements[$0].boundElements }
        guard !before.isEmpty else { return }
        let oldBounds = Set(before).compactMap { element($0)?.aabb }.reduce(CGRect.null) { $0.union($1) }
        let changed = ArrowBinding.updateArrows(boundTo: ids, in: &elements, index: indexById)
        var dirty = oldBounds
        for id in changed {
            guard let e = element(id) else { continue }
            spatial.insert(id, rect: e.aabb)
            dirty = dirty.union(e.aabb)
        }
        invalidate(dirty, strokeWidth: 8)
    }

    func setBinding(_ binding: PointBinding?, end: LinearEnd, arrowId: String) {
        ArrowBinding.setBinding(binding, end: end, arrowId: arrowId, in: &elements, index: indexById)
    }

    private func invalidate(_ rect: CGRect, strokeWidth: Double) {
        guard !rect.isNull else { return }
        // Rough strokes can wander a few units outside the geometric bounds; labels/arrowheads too.
        let slack = strokeWidth * 2 + 40
        onInvalidate?(rect.insetBy(dx: -slack, dy: -slack))
    }

    /// Marks committed content as changed for observers (property panel etc.).
    func touch() { revision += 1 }
}
