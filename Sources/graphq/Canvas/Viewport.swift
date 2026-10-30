import CoreGraphics
import Foundation

/// Maps scene coordinates to view coordinates: `view = (scene - origin) * zoom`.
struct Viewport: Equatable {
    /// Scene point shown at the view's top-left corner.
    var origin: CGPoint = .zero
    var zoom: CGFloat = 1

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 30

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) * zoom, y: (p.y - origin.y) * zoom)
    }

    func toScene(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / zoom + origin.x, y: p.y / zoom + origin.y)
    }

    func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin), size: CGSize(width: r.width * zoom, height: r.height * zoom))
    }

    func toScene(_ r: CGRect) -> CGRect {
        CGRect(origin: toScene(r.origin), size: CGSize(width: r.width / zoom, height: r.height / zoom))
    }

    /// Zooms to `newZoom` keeping the scene point under `anchor` (view coords) fixed.
    mutating func zoom(to newZoom: CGFloat, anchor: CGPoint) {
        let clamped = min(max(newZoom, Self.minZoom), Self.maxZoom)
        let scenePoint = toScene(anchor)
        zoom = clamped
        origin = CGPoint(x: scenePoint.x - anchor.x / clamped, y: scenePoint.y - anchor.y / clamped)
    }

    mutating func pan(byView delta: CGPoint) {
        origin.x -= delta.x / zoom
        origin.y -= delta.y / zoom
    }

    /// Fits `rect` (scene) into a view of `size` with padding, never zooming past `maxFitZoom`.
    mutating func fit(_ rect: CGRect, in size: CGSize, padding: CGFloat = 60, maxFitZoom: CGFloat = 1) {
        guard !rect.isNull, size.width > 0, size.height > 0 else { return }
        let w = max(rect.width, 1), h = max(rect.height, 1)
        let z = min((size.width - padding * 2) / w, (size.height - padding * 2) / h, maxFitZoom)
        zoom = min(max(z, Self.minZoom), Self.maxZoom)
        origin = CGPoint(x: rect.midX - size.width / 2 / zoom, y: rect.midY - size.height / 2 / zoom)
    }
}
