import CoreGraphics
import Foundation

/// Attachment of a linear element's endpoint to a bindable shape.
public struct PointBinding: Codable, Hashable, Sendable {
    public var elementId: String
    /// Point inside the target, normalized to its unrotated box (0...1 on both axes).
    /// The arrow aims at this point and stops at the shape outline.
    public var focus: CGPoint
    /// Distance between the arrow tip and the outline, in scene units.
    public var gap: Double

    public init(elementId: String, focus: CGPoint, gap: Double) {
        self.elementId = elementId
        self.focus = focus
        self.gap = gap
    }
}

/// A single drawable element. Value type: every mutation produces a new value,
/// which keeps undo snapshots, clipboard and rendering caches trivially correct.
public struct Element: Identifiable, Hashable, Sendable {
    public var id: String
    public var type: ElementType

    // Geometry (unrotated box; rotation is around the box center).
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Rotation in radians, clockwise in a y-down coordinate space.
    public var angle: Double

    // Style
    public var strokeColor: RGBAColor
    public var fillColor: RGBAColor
    public var fillStyle: FillStyle
    public var strokeWidth: Double
    public var strokeStyle: StrokeStyle
    /// 0 = architect, 1 = artist, 2 = cartoonist.
    public var roughness: Double
    /// 0...1
    public var opacity: Double
    /// Corner radius in scene units; 0 = sharp. Clamped to half the short side when drawn.
    public var roundness: Double

    /// Seed for the deterministic rough renderer.
    public var seed: Int
    /// Incremented on every change.
    public var version: Int
    /// Random value regenerated whenever the element's *shape* changes (anything but x/y).
    /// Render caches key on it: pure moves keep cached paths, and restoring an older
    /// snapshot (undo) brings back its own nonce, so a stale entry is never hit.
    public var versionNonce: Int

    /// Group membership, innermost first, outermost last.
    public var groupIds: [String]
    /// Ids of linear elements bound to this element.
    public var boundElements: [String]
    public var locked: Bool

    // Linear & freedraw: points relative to (x, y), normalized so their bbox starts at (0, 0).
    public var points: [CGPoint]
    public var pressures: [Double]
    public var simulatePressure: Bool
    public var startBinding: PointBinding?
    public var endBinding: PointBinding?
    public var startArrowhead: Arrowhead
    public var endArrowhead: Arrowhead
    /// Linear elements: draw a smooth curve through the points instead of a polyline.
    public var curved: Bool

    // Text (for text elements, and labels inside containers).
    public var text: String
    public var fontSize: Double
    public var fontFamily: FontFamily
    public var textAlign: TextAlign

    // Image
    public var fileId: String?

    public init(
        id: String = ElementID.make(),
        type: ElementType,
        x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0, angle: Double = 0,
        strokeColor: RGBAColor = .ink, fillColor: RGBAColor = .transparent,
        fillStyle: FillStyle = .hachure, strokeWidth: Double = 2, strokeStyle: StrokeStyle = .solid,
        roughness: Double = 1, opacity: Double = 1, roundness: Double = 0,
        seed: Int = ElementID.makeSeed(), version: Int = 1, versionNonce: Int = ElementID.makeSeed(),
        groupIds: [String] = [], boundElements: [String] = [], locked: Bool = false,
        points: [CGPoint] = [], pressures: [Double] = [], simulatePressure: Bool = true,
        startBinding: PointBinding? = nil, endBinding: PointBinding? = nil,
        startArrowhead: Arrowhead = .none, endArrowhead: Arrowhead = .none, curved: Bool = false,
        text: String = "", fontSize: Double = 20, fontFamily: FontFamily = .hand, textAlign: TextAlign = .center,
        fileId: String? = nil
    ) {
        self.id = id; self.type = type
        self.x = x; self.y = y; self.width = width; self.height = height; self.angle = angle
        self.strokeColor = strokeColor; self.fillColor = fillColor; self.fillStyle = fillStyle
        self.strokeWidth = strokeWidth; self.strokeStyle = strokeStyle; self.roughness = roughness
        self.opacity = opacity; self.roundness = roundness
        self.seed = seed; self.version = version; self.versionNonce = versionNonce
        self.groupIds = groupIds; self.boundElements = boundElements; self.locked = locked
        self.points = points; self.pressures = pressures; self.simulatePressure = simulatePressure
        self.startBinding = startBinding; self.endBinding = endBinding
        self.startArrowhead = startArrowhead; self.endArrowhead = endArrowhead; self.curved = curved
        self.text = text; self.fontSize = fontSize; self.fontFamily = fontFamily; self.textAlign = textAlign
        self.fileId = fileId
    }

    /// Marks the element as changed (new version + nonce) — call after every mutation.
    public mutating func bump() {
        version += 1
        versionNonce = ElementID.makeSeed()
    }

    /// Like `bump()`, but keeps the nonce when only the position changed relative to `old`.
    public mutating func bump(comparedTo old: Element) {
        version += 1
        var a = self, b = old
        a.x = 0; a.y = 0; b.x = 0; b.y = 0
        a.version = 0; b.version = 0
        a.versionNonce = 0; b.versionNonce = 0
        if a != b { versionNonce = ElementID.makeSeed() }
    }

    public var hasLabel: Bool { type.isContainer && !text.isEmpty }
}

// MARK: - Codable

extension Element: Codable {
    enum CodingKeys: String, CodingKey {
        case id, type, x, y, width, height, angle
        case strokeColor, fillColor, fillStyle, strokeWidth, strokeStyle, roughness, opacity, roundness
        case seed, version, versionNonce, groupIds, boundElements, locked
        case points, pressures, simulatePressure, startBinding, endBinding, startArrowhead, endArrowhead, curved
        case text, fontSize, fontFamily, textAlign, fileId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        self.init(
            id: try c.decode(String.self, forKey: .id),
            type: try c.decode(ElementType.self, forKey: .type),
            x: try v(.x, 0), y: try v(.y, 0), width: try v(.width, 0), height: try v(.height, 0),
            angle: try v(.angle, 0),
            strokeColor: try v(.strokeColor, .ink), fillColor: try v(.fillColor, .transparent),
            fillStyle: try v(.fillStyle, .hachure), strokeWidth: try v(.strokeWidth, 2),
            strokeStyle: try v(.strokeStyle, .solid), roughness: try v(.roughness, 1),
            opacity: try v(.opacity, 1), roundness: try v(.roundness, 0),
            seed: try v(.seed, ElementID.makeSeed()), version: try v(.version, 1),
            versionNonce: try v(.versionNonce, ElementID.makeSeed()),
            groupIds: try v(.groupIds, []), boundElements: try v(.boundElements, []), locked: try v(.locked, false),
            points: try v(.points, []), pressures: try v(.pressures, []), simulatePressure: try v(.simulatePressure, true),
            startBinding: try c.decodeIfPresent(PointBinding.self, forKey: .startBinding),
            endBinding: try c.decodeIfPresent(PointBinding.self, forKey: .endBinding),
            startArrowhead: try v(.startArrowhead, .none), endArrowhead: try v(.endArrowhead, .none),
            curved: try v(.curved, false),
            text: try v(.text, ""), fontSize: try v(.fontSize, 20), fontFamily: try v(.fontFamily, .hand),
            textAlign: try v(.textAlign, .center),
            fileId: try c.decodeIfPresent(String.self, forKey: .fileId)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(angle, forKey: .angle)
        try c.encode(strokeColor, forKey: .strokeColor)
        try c.encode(fillColor, forKey: .fillColor)
        try c.encode(fillStyle, forKey: .fillStyle)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokeStyle, forKey: .strokeStyle)
        try c.encode(roughness, forKey: .roughness)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(roundness, forKey: .roundness)
        try c.encode(seed, forKey: .seed)
        try c.encode(version, forKey: .version)
        try c.encode(versionNonce, forKey: .versionNonce)
        try c.encode(groupIds, forKey: .groupIds)
        if !boundElements.isEmpty { try c.encode(boundElements, forKey: .boundElements) }
        try c.encode(locked, forKey: .locked)
        if type.isLinear || type == .freedraw {
            try c.encode(points, forKey: .points)
        }
        if type == .freedraw {
            if !pressures.isEmpty { try c.encode(pressures, forKey: .pressures) }
            try c.encode(simulatePressure, forKey: .simulatePressure)
        }
        if type.isLinear {
            try c.encodeIfPresent(startBinding, forKey: .startBinding)
            try c.encodeIfPresent(endBinding, forKey: .endBinding)
            try c.encode(startArrowhead, forKey: .startArrowhead)
            try c.encode(endArrowhead, forKey: .endArrowhead)
            try c.encode(curved, forKey: .curved)
        }
        if type == .text || !text.isEmpty {
            try c.encode(text, forKey: .text)
            try c.encode(fontSize, forKey: .fontSize)
            try c.encode(fontFamily, forKey: .fontFamily)
            try c.encode(textAlign, forKey: .textAlign)
        }
        try c.encodeIfPresent(fileId, forKey: .fileId)
    }
}

// MARK: - IDs

public enum ElementID {
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-")

    public static func make(length: Int = 20) -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
    }

    /// Positive 31-bit seed, compatible with rough.js' LCG.
    public static func makeSeed() -> Int {
        Int.random(in: 1..<Int(Int32.max))
    }
}
