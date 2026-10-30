import CoreGraphics
import Foundation

public enum ColorRole: Sendable { case stroke, fill }

/// One drawable primitive in element-local coordinates.
public struct DrawItem: Sendable {
    public enum Kind: Sendable {
        case stroke(width: Double, dash: [Double]?)
        case fill
    }

    public var kind: Kind
    public var role: ColorRole
    public var ops: [PathOp]

    public init(kind: Kind, role: ColorRole, ops: [PathOp]) {
        self.kind = kind; self.role = role; self.ops = ops
    }
}

/// Turns an element into rough draw items. Pure and deterministic for a given element,
/// which is what makes per-element caching in the renderer safe.
public enum ShapeBuilder {
    /// Excalidraw tones down roughness for tiny shapes so they stay legible.
    static func adjustedRoughness(_ e: Element) -> Double {
        let maxSize = max(abs(e.width), abs(e.height))
        let minSize = min(abs(e.width), abs(e.height))
        if (minSize >= 20 && maxSize >= 50) || minSize == 0 && maxSize >= 50 || e.type.isLinear {
            return e.roughness
        }
        return min(e.roughness / (maxSize < 10 ? 3 : 2), 2.5)
    }

    public static func options(for e: Element) -> RoughOptions {
        var o = RoughOptions()
        o.seed = e.seed
        o.roughness = adjustedRoughness(e)
        o.strokeWidth = e.strokeStyle == .solid ? e.strokeWidth : e.strokeWidth + 0.5
        o.disableMultiStroke = e.strokeStyle != .solid
        o.fillWeight = e.strokeWidth / 2
        o.hachureGap = e.strokeWidth * 4
        o.preserveVertices = e.roughness < 2
        return o
    }

    public static func dashPattern(for e: Element) -> [Double]? {
        switch e.strokeStyle {
        case .solid: return nil
        case .dashed: return [8, 8 + e.strokeWidth]
        case .dotted: return [1.5, 6 + e.strokeWidth]
        }
    }

    public static func build(_ e: Element) -> [DrawItem] {
        switch e.type {
        case .rectangle, .diamond: return polygonShape(e)
        case .ellipse: return ellipseShape(e)
        case .arrow, .line: return linearShape(e)
        case .freedraw: return freedrawShape(e)
        case .text, .image: return []
        }
    }

    private static func strokeItem(_ e: Element, _ ops: [PathOp], o: RoughOptions) -> DrawItem {
        DrawItem(kind: .stroke(width: o.strokeWidth, dash: dashPattern(for: e)), role: .stroke, ops: ops)
    }

    private static func fillItems(_ e: Element, polygon: [CGPoint], gen: RoughGenerator) -> [DrawItem] {
        guard !e.fillColor.isTransparent else { return [] }
        switch e.fillStyle {
        case .solid:
            return [DrawItem(kind: .fill, role: .fill, ops: gen.solidFill(polygon))]
        case .hachure, .crossHatch:
            let ops = gen.hachureFill(polygon, crossHatch: e.fillStyle == .crossHatch)
            return [DrawItem(kind: .stroke(width: gen.o.fillWeight, dash: nil), role: .fill, ops: ops)]
        }
    }

    private static func polygonShape(_ e: Element) -> [DrawItem] {
        let o = options(for: e)
        let gen = RoughGenerator(options: o)
        let vertices = e.type == .diamond ? e.diamondVertices
            : CGRect(x: 0, y: 0, width: e.width, height: e.height).corners
        let r = e.effectiveRadius
        // Outline first so fill randomness never shifts the outline when the fill changes.
        let outline = r > 0 ? gen.roundedPolygon(vertices, radius: r) : gen.polygon(vertices)
        let fillGen = RoughGenerator(options: o)
        let fills = fillItems(e, polygon: e.localOutline, gen: fillGen)
        return fills + [strokeItem(e, outline, o: o)]
    }

    private static func ellipseShape(_ e: Element) -> [DrawItem] {
        let o = options(for: e)
        let gen = RoughGenerator(options: o)
        let solid = !e.fillColor.isTransparent && e.fillStyle == .solid
        let result = gen.ellipse(center: CGPoint(x: e.width / 2, y: e.height / 2),
                                 width: e.width, height: e.height, solidFill: solid)
        var items: [DrawItem] = []
        if let fill = result.fill {
            items.append(DrawItem(kind: .fill, role: .fill, ops: fill))
        } else if !e.fillColor.isTransparent {
            items += fillItems(e, polygon: result.stroke.estimatedPoints, gen: gen)
        }
        items.append(strokeItem(e, result.stroke.ops, o: o))
        return items
    }

    private static func linearShape(_ e: Element) -> [DrawItem] {
        guard e.points.count >= 2 else { return [] }
        let o = options(for: e)
        let gen = RoughGenerator(options: o)
        let body = e.curved && e.points.count > 2 ? gen.curve(e.points) : gen.linearPath(e.points, close: false)
        var items: [DrawItem] = []
        if e.isClosedPath && !e.fillColor.isTransparent {
            items += fillItems(e, polygon: e.localPath, gen: RoughGenerator(options: o))
        }
        items.append(strokeItem(e, body, o: o))
        if e.type == .arrow {
            items += Arrowheads.items(for: e, options: o)
        }
        return items
    }

    public static func freehandOptions(for e: Element) -> Freehand.Options {
        Freehand.Options(size: e.strokeWidth * 2.2 + 1.2, simulatePressure: e.simulatePressure, last: true)
    }

    private static func freedrawShape(_ e: Element) -> [DrawItem] {
        guard !e.points.isEmpty else { return [] }
        let outline = Freehand.outline(points: e.points, pressures: e.pressures, options: freehandOptions(for: e))
        return [DrawItem(kind: .fill, role: .stroke, ops: Freehand.pathOps(outline: outline))]
    }
}
