import CoreGraphics
import Foundation

public enum ResizeHandle: String, CaseIterable, Sendable {
    case nw, n, ne, e, se, s, sw, w

    /// Position of the handle on a unit box.
    public var factor: CGPoint {
        switch self {
        case .nw: CGPoint(x: 0, y: 0)
        case .n: CGPoint(x: 0.5, y: 0)
        case .ne: CGPoint(x: 1, y: 0)
        case .e: CGPoint(x: 1, y: 0.5)
        case .se: CGPoint(x: 1, y: 1)
        case .s: CGPoint(x: 0.5, y: 1)
        case .sw: CGPoint(x: 0, y: 1)
        case .w: CGPoint(x: 0, y: 0.5)
        }
    }

    public var isCorner: Bool { self == .nw || self == .ne || self == .se || self == .sw }
}

/// Resize/rotate math, independent of any UI.
public enum Transforms {
    public static let minSize: CGFloat = 1

    /// Result of dragging `handle` of `box` to `pointer` (same coordinate space).
    /// `flipX`/`flipY` report that the pointer crossed the opposite edge.
    public static func resizedBox(_ box: CGRect, handle: ResizeHandle, pointer: CGPoint,
                                  keepAspect: Bool, fromCenter: Bool) -> (rect: CGRect, flipX: Bool, flipY: Bool) {
        let f = handle.factor
        // Signed extents measured from the anchor (opposite side, or center).
        let anchorX = fromCenter ? box.midX : (f.x == 0 ? box.maxX : box.minX)
        let anchorY = fromCenter ? box.midY : (f.y == 0 ? box.maxY : box.minY)
        let dirX: CGFloat = f.x == 0 ? -1 : 1
        let dirY: CGFloat = f.y == 0 ? -1 : 1
        let k: CGFloat = fromCenter ? 2 : 1
        let baseW = max(box.width, minSize), baseH = max(box.height, minSize)

        var w = f.x == 0.5 ? baseW : (pointer.x - anchorX) * dirX * k
        var h = f.y == 0.5 ? baseH : (pointer.y - anchorY) * dirY * k

        if keepAspect {
            if handle.isCorner {
                let scale = max(abs(w) / baseW, abs(h) / baseH)
                w = (w < 0 ? -1 : 1) * baseW * scale
                h = (h < 0 ? -1 : 1) * baseH * scale
            } else if f.x == 0.5 {
                w = baseW * abs(h) / baseH
            } else {
                h = baseH * abs(w) / baseW
            }
        }
        let flipX = w < 0, flipY = h < 0
        w = max(abs(w), minSize)
        h = max(abs(h), minSize)

        // Place the new box relative to the anchor in the drag direction.
        let x: CGFloat
        if fromCenter || f.x == 0.5 {
            x = (fromCenter ? box.midX : box.midX) - w / 2
        } else {
            let sign = dirX * (flipX ? -1 : 1)
            x = sign > 0 ? anchorX : anchorX - w
        }
        let y: CGFloat
        if fromCenter || f.y == 0.5 {
            y = box.midY - h / 2
        } else {
            let sign = dirY * (flipY ? -1 : 1)
            y = sign > 0 ? anchorY : anchorY - h
        }
        return (CGRect(x: x, y: y, width: w, height: h), flipX, flipY)
    }

    /// Resizes a single (possibly rotated) element by one of its handles.
    /// The pointer is mapped into the element's unrotated frame, so the opposite
    /// handle stays fixed on screen regardless of rotation.
    public static func resize(_ e: Element, handle: ResizeHandle, pointer: CGPoint,
                              keepAspect: Bool, fromCenter: Bool) -> Element {
        let local = e.toLocal(pointer)
        let box = CGRect(x: 0, y: 0, width: e.width, height: e.height)
        let aspect = keepAspect || e.type == .text
        let (r, flipX, flipY) = resizedBox(box, handle: handle, pointer: local, keepAspect: aspect, fromCenter: fromCenter)
        let newCenter = e.toScene(r.center)
        var n = e
        n.width = r.width
        n.height = r.height
        n.x = newCenter.x - r.width / 2
        n.y = newCenter.y - r.height / 2
        if e.type.isLinear || e.type == .freedraw {
            let sx = e.width > 0 ? r.width / e.width : 1
            let sy = e.height > 0 ? r.height / e.height : 1
            n.points = e.points.map { p in
                var q = CGPoint(x: p.x * sx, y: p.y * sy)
                if flipX { q.x = r.width - q.x }
                if flipY { q.y = r.height - q.y }
                return q
            }
            if e.width == 0 { n.width = 0; n.x = newCenter.x }
            if e.height == 0 { n.height = 0; n.y = newCenter.y }
        }
        if e.type == .text, e.height > 0 {
            n.fontSize = max(1, e.fontSize * r.height / e.height)
        }
        return n
    }

    /// Scales several elements together inside their common bounds `bounds`.
    public static func resize(_ elements: [Element], bounds: CGRect, handle: ResizeHandle, pointer: CGPoint,
                              keepAspect: Bool, fromCenter: Bool) -> [Element] {
        let aspect = keepAspect || elements.contains { $0.type == .text }
        let (r, flipX, flipY) = resizedBox(bounds, handle: handle, pointer: pointer, keepAspect: aspect, fromCenter: fromCenter)
        let sx = bounds.width > 0 ? r.width / bounds.width : 1
        let sy = bounds.height > 0 ? r.height / bounds.height : 1
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: r.minX + (flipX ? bounds.maxX - p.x : p.x - bounds.minX) * sx,
                    y: r.minY + (flipY ? bounds.maxY - p.y : p.y - bounds.minY) * sy)
        }
        return elements.map { e in
            var n = e
            if e.type.isLinear || e.type == .freedraw {
                n.setAbsolutePoints(e.absolutePoints.map(map))
                return n
            }
            let c = map(e.center)
            n.width = max(e.width * sx, minSize)
            n.height = max(e.height * sy, minSize)
            n.x = c.x - n.width / 2
            n.y = c.y - n.height / 2
            if flipX != flipY { n.angle = -e.angle }
            if e.type == .text { n.fontSize = max(1, e.fontSize * sy) }
            return n
        }
    }

    /// Rotates elements rigidly around `center`.
    public static func rotate(_ elements: [Element], around center: CGPoint, by delta: CGFloat) -> [Element] {
        elements.map { e in
            var n = e
            let c = e.center.rotated(around: center, by: delta)
            n.x = c.x - e.width / 2
            n.y = c.y - e.height / 2
            n.angle = normalizeAngle(e.angle + delta)
            return n
        }
    }

    public static func normalizeAngle(_ a: CGFloat) -> CGFloat {
        var v = a.truncatingRemainder(dividingBy: 2 * .pi)
        if v < 0 { v += 2 * .pi }
        if abs(v - 2 * .pi) < 1e-9 { v = 0 }
        return v
    }
}
