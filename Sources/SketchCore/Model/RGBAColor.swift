import Foundation

/// Platform-independent color stored as sRGB components in 0...1.
/// Serialized as a hex string (`#rrggbb` or `#rrggbbaa`), `"transparent"` for clear.
public struct RGBAColor: Hashable, Sendable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let transparent = RGBAColor(r: 0, g: 0, b: 0, a: 0)
    public static let black = RGBAColor(r: 0, g: 0, b: 0)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)
    /// Default ink color — a soft near-black rather than pure black.
    public static let ink = RGBAColor(hex: "#1f2328")!

    public var isTransparent: Bool { a <= 0.001 }

    // MARK: Hex

    public init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s == "transparent" { self = .transparent; return }
        if let named = RGBAColor.cssNames[s] { s = named }
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            r = Double((v >> 16) & 0xff) / 255
            g = Double((v >> 8) & 0xff) / 255
            b = Double(v & 0xff) / 255
            a = 1
        } else {
            r = Double((v >> 24) & 0xff) / 255
            g = Double((v >> 16) & 0xff) / 255
            b = Double((v >> 8) & 0xff) / 255
            a = Double(v & 0xff) / 255
        }
    }

    public var hexString: String {
        if isTransparent { return "transparent" }
        func c(_ v: Double) -> String { String(format: "%02x", Int((max(0, min(1, v)) * 255).rounded())) }
        return a >= 0.999 ? "#\(c(r))\(c(g))\(c(b))" : "#\(c(r))\(c(g))\(c(b))\(c(a))"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = RGBAColor(hex: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid color \(s)")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hexString)
    }

    public func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }

    private static let cssNames: [String: String] = [
        "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000",
        "blue": "#0000ff", "yellow": "#ffff00", "gray": "#808080", "grey": "#808080",
        "orange": "#ffa500", "purple": "#800080", "pink": "#ffc0cb",
    ]

    // MARK: HSL

    public var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        switch maxC {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    public init(h: Double, s: Double, l: Double, a: Double = 1) {
        guard s > 0 else { self.init(r: l, g: l, b: l, a: a); return }
        func hue(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(r: hue(p, q, h + 1.0 / 3), g: hue(p, q, h), b: hue(p, q, h - 1.0 / 3), a: a)
    }

    /// "Smart" dark-mode adaptation: lightness is mirrored while hue is preserved,
    /// so dark ink becomes light ink, pastel fills become deep tints, and a red stays red.
    /// Mid-tones are nudged slightly brighter to keep contrast on a dark canvas.
    public func adaptedForDarkMode() -> RGBAColor {
        if isTransparent { return self }
        let (h, s, l) = hsl
        var nl = 1 - l
        // Keep saturated mid-tones readable: never let them sink below 0.55 lightness.
        if s > 0.25 && l > 0.3 && l < 0.7 { nl = max(nl, 0.6) }
        // Very light fills become deep, low-lightness tints instead of black.
        nl = min(max(nl, s > 0.15 ? 0.26 : 0.12), 0.93)
        // Pastels become calm, desaturated deep tints rather than neon darks.
        let ns = l > 0.75 ? s * 0.4 : (s > 0.25 ? min(1, s * 0.85) : s)
        return RGBAColor(h: h, s: ns, l: nl, a: a)
    }
}
