import CoreGraphics
import SketchCore

/// Geometry of the selection chrome (box, handles), shared by the selection tool
/// for hit-testing and by the canvas for drawing.
struct SelectionFrame {
    /// Unrotated box in scene space.
    var rect: CGRect
    var angle: CGFloat
    /// Set when the selection is exactly one element.
    var single: Element?
    var showsHandles: Bool
    /// Text only gets corner handles.
    var cornersOnly: Bool

    var center: CGPoint { rect.center }

    func toScene(_ p: CGPoint) -> CGPoint { p.rotated(around: center, by: angle) }

    /// Handle positions in scene space for the given zoom (box padded by a few screen pixels).
    func handles(zoom: CGFloat) -> [(ResizeHandle, CGPoint)] {
        guard showsHandles else { return [] }
        let pad = 4 / zoom
        let box = rect.insetBy(dx: -pad, dy: -pad)
        let small = rect.width * zoom < 30 || rect.height * zoom < 30
        return ResizeHandle.allCases.compactMap { h in
            if (cornersOnly || small) && !h.isCorner { return nil }
            let f = h.factor
            return (h, toScene(CGPoint(x: box.minX + box.width * f.x, y: box.minY + box.height * f.y)))
        }
    }

    func rotationHandle(zoom: CGFloat) -> CGPoint? {
        guard showsHandles else { return nil }
        let pad = 4 / zoom
        return toScene(CGPoint(x: rect.midX, y: rect.minY - pad - 22 / zoom))
    }

    /// Corners of the (padded) frame in scene space, for drawing the outline.
    func outline(zoom: CGFloat) -> [CGPoint] {
        let pad = 4 / zoom
        return rect.insetBy(dx: -pad, dy: -pad).corners.map(toScene)
    }

    @MainActor
    static func make(for store: SceneStore) -> SelectionFrame? {
        let selected = store.selectedElements
        guard !selected.isEmpty else { return nil }
        let anyLocked = selected.contains(where: \.locked)
        if selected.count == 1, let e = selected.first {
            let linear = e.type.isLinear && e.points.count >= 2
            return SelectionFrame(rect: e.rect, angle: e.angle, single: e,
                                  showsHandles: !anyLocked && !linear,
                                  cornersOnly: e.type == .text)
        }
        return SelectionFrame(rect: SceneGeometry.bounds(of: selected), angle: 0, single: nil,
                              showsHandles: !anyLocked, cornersOnly: false)
    }
}
