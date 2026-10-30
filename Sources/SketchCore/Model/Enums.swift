import Foundation

public enum ElementType: String, Codable, Sendable, CaseIterable {
    case rectangle, ellipse, diamond, arrow, line, freedraw, text, image

    /// Shapes with a closed outline that can hold a label and accept arrow bindings.
    public var isContainer: Bool { self == .rectangle || self == .ellipse || self == .diamond }
    public var isLinear: Bool { self == .arrow || self == .line }
    public var isBindable: Bool { isContainer || self == .text || self == .image }
    public var supportsFill: Bool { isContainer || self == .line }
}

public enum FillStyle: String, Codable, Sendable, CaseIterable {
    case hachure
    case crossHatch = "cross-hatch"
    case solid

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FillStyle(rawValue: raw) ?? .hachure
    }
}

public enum StrokeStyle: String, Codable, Sendable, CaseIterable {
    case solid, dashed, dotted

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StrokeStyle(rawValue: raw) ?? .solid
    }
}

public enum Arrowhead: String, Codable, Sendable, CaseIterable {
    case none, arrow, triangle, dot, bar, diamond

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Arrowhead(rawValue: raw) ?? .arrow
    }
}

public enum FontFamily: String, Codable, Sendable, CaseIterable {
    /// Hand-drawn (Virgil).
    case hand
    /// System UI font (SF Pro).
    case normal
    /// System monospace (SF Mono).
    case mono

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FontFamily(rawValue: raw) ?? .hand
    }
}

public enum TextAlign: String, Codable, Sendable, CaseIterable {
    case left, center, right

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TextAlign(rawValue: raw) ?? .left
    }
}

/// Sloppiness presets. Values match Excalidraw's roughness levels.
public enum Sloppiness: Double, CaseIterable, Sendable {
    case architect = 0
    case artist = 1
    case cartoonist = 2

    public init(roughness: Double) {
        if roughness < 0.5 { self = .architect } else if roughness < 1.5 { self = .artist } else { self = .cartoonist }
    }
}
