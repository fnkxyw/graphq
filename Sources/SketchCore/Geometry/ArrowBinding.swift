import CoreGraphics
import Foundation

public enum LinearEnd: Sendable { case start, end }

/// Arrow ↔ shape binding: arrows aim at a focus point inside the target
/// and stop at its outline, so they follow the shape when it moves or resizes.
public enum ArrowBinding {
    public static let defaultGap: CGFloat = 6

    /// Topmost bindable element under `p` (elements ordered back → front).
    public static func target(at p: CGPoint, in elements: [Element], excluding: Set<String>, threshold: CGFloat) -> Element? {
        for e in elements.reversed() where e.type.isBindable && !excluding.contains(e.id) && !e.locked {
            if HitTest.isInside(e, p, padding: threshold) { return e }
        }
        return nil
    }

    /// Binding that aims at `p` (clamped into the target box).
    public static func makeBinding(to target: Element, at p: CGPoint, gap: CGFloat = defaultGap) -> PointBinding {
        let local = target.toLocal(p)
        let fx = target.width > 0 ? min(max(local.x / target.width, 0), 1) : 0.5
        let fy = target.height > 0 ? min(max(local.y / target.height, 0), 1) : 0.5
        // Pull the focus slightly toward the center so the aim line always enters the shape.
        let pull: CGFloat = 0.1
        return PointBinding(
            elementId: target.id,
            focus: CGPoint(x: fx + (0.5 - fx) * pull, y: fy + (0.5 - fy) * pull),
            gap: gap
        )
    }

    public static func focusPoint(_ b: PointBinding, on target: Element) -> CGPoint {
        target.toScene(CGPoint(x: b.focus.x * target.width, y: b.focus.y * target.height))
    }

    /// Where a bound endpoint should sit, given the neighbouring point it is drawn from.
    public static func boundEndpoint(_ b: PointBinding, target: Element, reference: CGPoint) -> CGPoint {
        let focus = focusPoint(b, on: target)
        if HitTest.isInside(target, reference) { return focus }
        guard let hit = Intersections.outline(of: target, from: reference, to: focus) else { return focus }
        let dir = (reference - hit).normalized
        return hit + dir * b.gap
    }

    /// Recomputes both endpoints of a linear element from its bindings
    /// (and re-routes elbow arrows).
    public static func updateEndpoints(of arrow: inout Element, lookup: (String) -> Element?) {
        if arrow.elbowed {
            routeElbow(&arrow, lookup: lookup)
            return
        }
        var pts = arrow.absolutePoints
        guard pts.count >= 2 else { return }
        let n = pts.count
        let startTarget = arrow.startBinding.flatMap { lookup($0.elementId) }
        let endTarget = arrow.endBinding.flatMap { lookup($0.elementId) }
        guard startTarget != nil || endTarget != nil else { return }

        let startRef: CGPoint
        let endRef: CGPoint
        if n > 2 {
            startRef = pts[1]
            endRef = pts[n - 2]
        } else {
            // Straight 2-point arrows aim at the other end's focus point.
            startRef = endTarget.map { focusPoint(arrow.endBinding!, on: $0) } ?? pts[n - 1]
            endRef = startTarget.map { focusPoint(arrow.startBinding!, on: $0) } ?? pts[0]
        }
        if let t = startTarget, let b = arrow.startBinding {
            pts[0] = boundEndpoint(b, target: t, reference: startRef)
        }
        if let t = endTarget, let b = arrow.endBinding {
            pts[n - 1] = boundEndpoint(b, target: t, reference: endRef)
        }
        arrow.setAbsolutePoints(pts)
    }

    /// Elbow arrows: bound ends attach to the side of the target facing the other end,
    /// then the path is re-routed orthogonally.
    static func routeElbow(_ arrow: inout Element, lookup: (String) -> Element?) {
        let pts = arrow.absolutePoints
        guard let first = pts.first, let last = pts.last, pts.count >= 2 else { return }
        let startTarget = arrow.startBinding.flatMap { lookup($0.elementId) }
        let endTarget = arrow.endBinding.flatMap { lookup($0.elementId) }
        // What each end "looks at": the other target's center, or the other free endpoint.
        let startRef = endTarget?.aabb.center ?? last
        let endRef = startTarget?.aabb.center ?? first

        var start = first, end = last
        var sh = ElbowRouter.heading(from: first, toward: last)
        var eh = ElbowRouter.heading(from: last, toward: first)
        if let t = startTarget, let b = arrow.startBinding {
            let box = t.aabb
            sh = ElbowRouter.side(of: box, facing: startRef)
            start = ElbowRouter.attachPoint(on: box, side: sh, focus: focusPoint(b, on: t), gap: b.gap)
        }
        if let t = endTarget, let b = arrow.endBinding {
            let box = t.aabb
            eh = ElbowRouter.side(of: box, facing: endRef)
            end = ElbowRouter.attachPoint(on: box, side: eh, focus: focusPoint(b, on: t), gap: b.gap)
        }
        if startTarget == nil { sh = ElbowRouter.heading(from: start, toward: end) }
        if endTarget == nil { eh = ElbowRouter.heading(from: end, toward: start) }
        // Elbow arrows are always axis-aligned.
        arrow.angle = 0
        arrow.setAbsolutePoints(ElbowRouter.route(start: start, startHeading: sh, end: end, endHeading: eh))
    }

    /// Updates every linear element bound to one of `targetIds`. Returns ids of changed arrows.
    @discardableResult
    public static func updateArrows(boundTo targetIds: Set<String>, in elements: inout [Element], index: [String: Int]) -> Set<String> {
        var arrowIds = Set<String>()
        for id in targetIds {
            guard let i = index[id] else { continue }
            arrowIds.formUnion(elements[i].boundElements)
        }
        var changed = Set<String>()
        for arrowId in arrowIds {
            guard let ai = index[arrowId], elements[ai].type.isLinear else { continue }
            var arrow = elements[ai]
            updateEndpoints(of: &arrow) { id in index[id].map { elements[$0] } }
            if arrow.points != elements[ai].points || arrow.x != elements[ai].x || arrow.y != elements[ai].y {
                arrow.bump()
                elements[ai] = arrow
                changed.insert(arrowId)
            }
        }
        return changed
    }

    /// Sets/clears the binding on one end and keeps the targets' `boundElements` in sync.
    public static func setBinding(_ binding: PointBinding?, end: LinearEnd, arrowId: String,
                                  in elements: inout [Element], index: [String: Int]) {
        guard let ai = index[arrowId] else { return }
        let old = end == .start ? elements[ai].startBinding : elements[ai].endBinding
        if end == .start { elements[ai].startBinding = binding } else { elements[ai].endBinding = binding }
        elements[ai].bump()

        let arrow = elements[ai]
        if let oldId = old?.elementId, oldId != binding?.elementId,
           arrow.startBinding?.elementId != oldId, arrow.endBinding?.elementId != oldId,
           let ti = index[oldId] {
            elements[ti].boundElements.removeAll { $0 == arrowId }
            elements[ti].bump()
        }
        if let newId = binding?.elementId, let ti = index[newId], !elements[ti].boundElements.contains(arrowId) {
            elements[ti].boundElements.append(arrowId)
            elements[ti].bump()
        }
    }

    /// Removes dangling references after elements were deleted.
    public static func cleanup(in elements: inout [Element]) {
        let ids = Set(elements.map(\.id))
        for i in elements.indices {
            var e = elements[i]
            var changed = false
            if let b = e.startBinding, !ids.contains(b.elementId) { e.startBinding = nil; changed = true }
            if let b = e.endBinding, !ids.contains(b.elementId) { e.endBinding = nil; changed = true }
            let bound = e.boundElements.filter { ids.contains($0) }
            if bound.count != e.boundElements.count { e.boundElements = bound; changed = true }
            if changed { e.bump(); elements[i] = e }
        }
        // Drop back-references that the arrows themselves no longer claim.
        var claims = [String: Set<String>]()
        for e in elements where e.type.isLinear {
            if let b = e.startBinding { claims[b.elementId, default: []].insert(e.id) }
            if let b = e.endBinding { claims[b.elementId, default: []].insert(e.id) }
        }
        for i in elements.indices where !elements[i].boundElements.isEmpty {
            let valid = elements[i].boundElements.filter { claims[elements[i].id]?.contains($0) == true }
            if valid.count != elements[i].boundElements.count {
                elements[i].boundElements = valid
                elements[i].bump()
            }
        }
    }
}
