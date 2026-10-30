import CoreGraphics
import Foundation

public extension Element {
    /// Unrotated box in scene coordinates.
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
    var size: CGSize { CGSize(width: width, height: height) }

    /// Element-local point (relative to the unrotated top-left) → scene.
    func toScene(_ local: CGPoint) -> CGPoint {
        CGPoint(x: x + local.x, y: y + local.y).rotated(around: center, by: angle)
    }

    /// Scene point → element-local (unrotated, relative to top-left).
    func toLocal(_ scene: CGPoint) -> CGPoint {
        let p = scene.rotated(around: center, by: -angle)
        return CGPoint(x: p.x - x, y: p.y - y)
    }

    /// Points of linear/freedraw elements in scene space.
    var absolutePoints: [CGPoint] { points.map(toScene) }

    /// Replaces points with scene-space points, re-normalizing x/y/width/height
    /// while keeping the current rotation and the visual position of every point.
    mutating func setAbsolutePoints(_ scenePoints: [CGPoint]) {
        guard !scenePoints.isEmpty else { points = []; width = 0; height = 0; return }
        // Work in a frame rotated by -angle around the origin; the bbox there is axis-aligned.
        let unrotated = scenePoints.map { $0.rotated(around: .zero, by: -angle) }
        let box = CGRect(enclosing: unrotated)
        let centerScene = box.center.rotated(around: .zero, by: angle)
        width = box.width
        height = box.height
        x = centerScene.x - box.width / 2
        y = centerScene.y - box.height / 2
        points = unrotated.map { CGPoint(x: $0.x - box.minX, y: $0.y - box.minY) }
    }

    /// Corner radius actually used for drawing.
    var effectiveRadius: CGFloat {
        guard roundness > 0 else { return 0 }
        let limit = type == .diamond ? min(width, height) / 4 : min(width, height) / 2
        return max(0, min(roundness, limit))
    }

    /// Diamond vertices in local coordinates: top, right, bottom, left.
    var diamondVertices: [CGPoint] {
        [CGPoint(x: width / 2, y: 0), CGPoint(x: width, y: height / 2),
         CGPoint(x: width / 2, y: height), CGPoint(x: 0, y: height / 2)]
    }

    /// Closed outline polygon in local coordinates (for containers/text/images).
    var localOutline: [CGPoint] {
        let local = CGRect(x: 0, y: 0, width: width, height: height)
        switch type {
        case .ellipse:
            return Curves.ellipsePoints(in: local)
        case .diamond:
            return Curves.roundedPolygonPoints(diamondVertices, radius: effectiveRadius)
        case .rectangle:
            return Curves.roundedPolygonPoints(local.corners, radius: effectiveRadius)
        default:
            return local.corners
        }
    }

    /// Polyline of what is actually drawn for linear elements (curves are flattened).
    var localPath: [CGPoint] {
        if type.isLinear && curved && !elbowed && points.count > 2 {
            return Curves.sampleCatmullRom(points)
        }
        return points
    }

    /// Axis-aligned bounding box in scene space, including rotation.
    var aabb: CGRect {
        switch type {
        case .arrow, .line, .freedraw:
            let pts = localPath.map(toScene)
            return pts.isEmpty ? CGRect(x: x, y: y, width: 0, height: 0) : CGRect(enclosing: pts)
        default:
            if angle == 0 { return rect.standardized }
            return CGRect(enclosing: CGRect(x: 0, y: 0, width: width, height: height).corners.map(toScene))
        }
    }

    /// Whether the linear element forms a closed loop (first ≈ last point).
    var isClosedPath: Bool {
        guard type == .line, points.count >= 3, let f = points.first, let l = points.last else { return false }
        return f.distance(to: l) < max(4, strokeWidth * 2)
    }

    mutating func move(by delta: CGPoint) {
        x += delta.x
        y += delta.y
    }
}

public enum SceneGeometry {
    /// Common AABB of several elements.
    public static func bounds(of elements: some Sequence<Element>) -> CGRect {
        elements.reduce(CGRect.null) { $0.union($1.aabb) }
    }
}
