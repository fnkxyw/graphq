import CoreGraphics
import Foundation

public enum HitTest {
    /// Whether scene point `p` hits element `e`. `tolerance` is in scene units
    /// (callers pass a screen-space tolerance divided by zoom).
    public static func hits(_ e: Element, _ p: CGPoint, tolerance: CGFloat) -> Bool {
        // Cheap reject on the rotated bounding box first.
        let slop = tolerance + e.strokeWidth
        guard e.aabb.insetBy(dx: -slop, dy: -slop).contains(p) else { return false }

        let local = e.toLocal(p)
        switch e.type {
        case .rectangle, .ellipse, .diamond:
            let outline = e.localOutline
            let filled = !e.fillColor.isTransparent || e.hasLabel
            if filled && Polygon.contains(outline, local) { return true }
            return Polygon.distanceToOutline(outline, local) <= tolerance + e.strokeWidth / 2
        case .text, .image:
            return CGRect(x: 0, y: 0, width: e.width, height: e.height)
                .insetBy(dx: -tolerance, dy: -tolerance).contains(local)
        case .arrow, .line:
            let path = e.localPath
            if e.isClosedPath && !e.fillColor.isTransparent && Polygon.contains(path, local) { return true }
            return Polygon.distanceToOutline(path, local, closed: false) <= tolerance + e.strokeWidth / 2
        case .freedraw:
            if e.points.count == 1 { return local.distance(to: e.points[0]) <= tolerance + e.strokeWidth * 2 }
            return Polygon.distanceToOutline(e.points, local, closed: false) <= tolerance + e.strokeWidth * 2
        }
    }

    /// Whether `p` is anywhere inside the element's area (used for binding and text-tool targeting).
    public static func isInside(_ e: Element, _ p: CGPoint, padding: CGFloat = 0) -> Bool {
        let local = e.toLocal(p)
        switch e.type {
        case .rectangle, .ellipse, .diamond:
            if Polygon.contains(e.localOutline, local) { return true }
            return padding > 0 && Polygon.distanceToOutline(e.localOutline, local) <= padding
        case .text, .image:
            return CGRect(x: 0, y: 0, width: e.width, height: e.height)
                .insetBy(dx: -padding, dy: -padding).contains(local)
        default:
            return false
        }
    }

    /// Marquee selection: element must be fully enclosed.
    public static func isEnclosed(_ e: Element, by rect: CGRect) -> Bool {
        rect.contains(e.aabb)
    }
}
