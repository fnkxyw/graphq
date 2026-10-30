import AppKit
import SketchCore
import SketchRender

extension CanvasView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bg = renderer.theme.background
        ctx.setFillColor(CGColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: 1))
        ctx.fill(dirtyRect)

        let zoom = viewport.zoom
        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -viewport.origin.x, y: -viewport.origin.y)

        let sceneDirty = viewport.toScene(dirtyRect)
        if store.settings.gridEnabled { drawGrid(in: ctx, rect: sceneDirty) }

        // Cull with the spatial index; pad for rough strokes that wander past the AABB.
        let editingId = textEditor?.elementId
        let visible = store.elements(in: sceneDirty.insetBy(dx: -24, dy: -24))
        for e in visible {
            let faded = fadedIds.contains(e.id)
            if faded {
                ctx.saveGState()
                ctx.setAlpha(0.25)
            }
            renderer.draw(e, in: ctx, files: store.files, hideText: e.id == editingId)
            if faded { ctx.restoreGState() }
        }

        drawBindingHighlight(in: ctx, zoom: zoom)
        drawSelection(in: ctx, zoom: zoom)
        drawGuides(in: ctx, zoom: zoom)
        tool.drawOverlay(in: ctx, zoom: zoom)
        ctx.restoreGState()
    }

    // MARK: Grid

    private func drawGrid(in ctx: CGContext, rect: CGRect) {
        var spacing = Snapping.gridSize
        // Coarsen the grid when zoomed out so dots never become noise.
        while spacing * viewport.zoom < 12 { spacing *= 5 }
        let dot = 1.6 / viewport.zoom
        let color: NSColor = isDark ? .white.withAlphaComponent(0.13) : .black.withAlphaComponent(0.16)
        ctx.setFillColor(color.cgColor)
        let x0 = floor(rect.minX / spacing) * spacing
        let y0 = floor(rect.minY / spacing) * spacing
        var rects: [CGRect] = []
        var y = y0
        while y <= rect.maxY {
            var x = x0
            while x <= rect.maxX {
                rects.append(CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                x += spacing
            }
            y += spacing
        }
        ctx.fill(rects)
    }

    // MARK: Selection chrome

    private var accent: CGColor { NSColor.controlAccentColor.cgColor }

    private func strokePolygon(_ ctx: CGContext, _ pts: [CGPoint]) {
        guard let f = pts.first else { return }
        ctx.beginPath()
        ctx.move(to: f)
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.closePath()
        ctx.strokePath()
    }

    private func drawSelection(in ctx: CGContext, zoom: CGFloat) {
        guard textEditor == nil || store.selection.count > 1 else { return }
        let selected = store.selectedElements
        guard !selected.isEmpty, let frame = SelectionFrame.make(for: store) else { return }
        ctx.saveGState()
        ctx.setLineWidth(1 / zoom)
        let anyLocked = selected.contains(where: \.locked)
        let color = anyLocked ? NSColor.secondaryLabelColor.cgColor : accent

        if selected.count > 1 {
            // Individual outlines, then a dashed box around everything.
            ctx.setStrokeColor(color.copy(alpha: 0.45) ?? color)
            for e in selected {
                let pad = 2 / zoom
                strokePolygon(ctx, CGRect(x: 0, y: 0, width: e.width, height: e.height)
                    .insetBy(dx: -pad, dy: -pad).corners.map(e.toScene))
            }
            ctx.setStrokeColor(color)
            ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
            strokePolygon(ctx, frame.outline(zoom: zoom))
            ctx.setLineDash(phase: 0, lengths: [])
        } else if let e = frame.single {
            if e.type.isLinear && e.points.count >= 2 {
                drawLinearHandles(e, in: ctx, zoom: zoom, locked: e.locked)
            } else {
                ctx.setStrokeColor(color)
                if e.locked { ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom]) }
                strokePolygon(ctx, frame.outline(zoom: zoom))
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }

        // Handles.
        let size = 8 / zoom
        for (_, p) in frame.handles(zoom: zoom) {
            let r = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
            let path = CGPath(roundedRect: r, cornerWidth: 2 / zoom, cornerHeight: 2 / zoom, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(accent)
            ctx.strokePath()
        }
        if let rp = frame.rotationHandle(zoom: zoom) {
            let r = CGRect(x: rp.x - size / 2, y: rp.y - size / 2, width: size, height: size)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(accent)
            ctx.strokeEllipse(in: r)
        }

        if let g = store.editingGroupId {
            let members = store.elements.filter { $0.groupIds.contains(g) }
            let box = SceneGeometry.bounds(of: members).insetBy(dx: -8 / zoom, dy: -8 / zoom)
            ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
            ctx.setLineDash(phase: 0, lengths: [2 / zoom, 4 / zoom])
            ctx.stroke(box)
        }
        ctx.restoreGState()
    }

    private func drawLinearHandles(_ e: Element, in ctx: CGContext, zoom: CGFloat, locked: Bool) {
        let pts = e.absolutePoints
        // Faint outline of the path's bounds for orientation.
        ctx.setStrokeColor(accent.copy(alpha: 0.25) ?? accent)
        ctx.stroke(e.aabb.insetBy(dx: -4 / zoom, dy: -4 / zoom))
        guard !locked else { return }
        let r = 4.5 / zoom
        if let selection = tool as? SelectionTool, !e.elbowed {
            let mr = 3.5 / zoom
            ctx.setFillColor(accent.copy(alpha: 0.35) ?? accent)
            for i in 0..<(pts.count - 1) {
                let m = selection.midpoint(of: e, segment: i)
                ctx.fillEllipse(in: CGRect(x: m.x - mr, y: m.y - mr, width: mr * 2, height: mr * 2))
            }
        }
        for (i, p) in pts.enumerated() where !e.elbowed || i == 0 || i == pts.count - 1 {
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            let bound = (i == 0 && e.startBinding != nil) || (i == pts.count - 1 && e.endBinding != nil)
            ctx.setFillColor(bound ? accent : NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(accent)
            ctx.strokeEllipse(in: rect)
        }
    }

    private func drawBindingHighlight(in ctx: CGContext, zoom: CGFloat) {
        guard let id = bindingHighlight, let e = store.element(id) else { return }
        ctx.saveGState()
        ctx.setStrokeColor(accent.copy(alpha: 0.35) ?? accent)
        ctx.setLineWidth(6 / zoom)
        ctx.setLineJoin(.round)
        let pad = 3 / zoom
        let outline: [CGPoint]
        if e.type.isContainer {
            let scale = CGAffineTransform(translationX: e.width / 2, y: e.height / 2)
                .scaledBy(x: (e.width + pad * 2) / max(e.width, 1), y: (e.height + pad * 2) / max(e.height, 1))
                .translatedBy(x: -e.width / 2, y: -e.height / 2)
            outline = e.localOutline.map { e.toScene($0.applying(scale)) }
        } else {
            outline = CGRect(x: 0, y: 0, width: e.width, height: e.height).insetBy(dx: -pad, dy: -pad).corners.map(e.toScene)
        }
        strokePolygon(ctx, outline)
        ctx.restoreGState()
    }

    private func drawGuides(in ctx: CGContext, zoom: CGFloat) {
        guard !snapGuides.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemPink.cgColor)
        ctx.setLineWidth(1 / zoom)
        for g in snapGuides {
            ctx.move(to: g.from)
            ctx.addLine(to: g.to)
            // Small crosses at the ends, like design tools do.
            let s = 3 / zoom
            for p in [g.from, g.to] {
                ctx.move(to: CGPoint(x: p.x - s, y: p.y - s)); ctx.addLine(to: CGPoint(x: p.x + s, y: p.y + s))
                ctx.move(to: CGPoint(x: p.x - s, y: p.y + s)); ctx.addLine(to: CGPoint(x: p.x + s, y: p.y - s))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
