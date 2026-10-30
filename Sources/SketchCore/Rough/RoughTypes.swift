import CoreGraphics
import Foundation

/// Renderer-agnostic path command. Converted to CGPath or SVG `d` by the render layer.
public enum PathOp: Hashable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case curve(CGPoint, CGPoint, CGPoint)
}

public enum OpSetKind: Sendable {
    /// Outline, stroked with the element's stroke width.
    case stroke
    /// Hachure/cross-hatch lines, stroked with the fill weight.
    case fillSketch
    /// Closed area, filled.
    case fillPath
}

public struct OpSet: Sendable {
    public var kind: OpSetKind
    public var ops: [PathOp]
    public init(kind: OpSetKind, ops: [PathOp]) { self.kind = kind; self.ops = ops }
}

/// Deterministic LCG matching rough.js (`Math.imul(48271, seed)`), so a stored seed
/// always produces the same wobble.
public struct RoughRandom: Sendable {
    private var seed: Int32

    public init(seed: Int) {
        let s = Int32(truncatingIfNeeded: seed)
        self.seed = s == 0 ? 1 : s
    }

    public mutating func next() -> Double {
        seed = seed &* 48271
        return Double(Int32.max & seed) / 2_147_483_648.0
    }
}

public struct RoughOptions: Sendable {
    public var roughness: Double = 1
    public var bowing: Double = 1
    public var maxRandomnessOffset: Double = 2
    public var strokeWidth: Double = 1
    public var curveFitting: Double = 0.95
    public var curveTightness: Double = 0
    public var curveStepCount: Double = 9
    public var hachureAngle: Double = -41
    public var hachureGap: Double = -1
    public var fillWeight: Double = -1
    public var disableMultiStroke: Bool = false
    public var disableMultiStrokeFill: Bool = false
    public var preserveVertices: Bool = false
    public var seed: Int = 1

    public init() {}
}
