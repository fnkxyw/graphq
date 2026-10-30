import AppKit
import CoreText
import Foundation
import SketchCore

/// Resolves fonts for the three families. Virgil (SIL OFL 1.1) ships as a resource;
/// if it can't be found the hand family falls back to Chalkboard SE, which ships with macOS.
public enum Fonts {
    private static let state = FontState()

    /// Locates the SwiftPM resource bundle without `Bundle.module`, which would crash
    /// when the app is repackaged into a .app (the bundle then lives in Contents/Resources).
    static var resourceBundle: Bundle? {
        let name = "graphq_SketchRender.bundle"
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent(name)) }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(name))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exe.appendingPathComponent(name))
        }
        for b in [Bundle(for: BundleToken.self)] + Bundle.allBundles + Bundle.allFrameworks {
            candidates.append(b.bundleURL.deletingLastPathComponent().appendingPathComponent(name))
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let b = Bundle(url: url) { return b }
        }
        return nil
    }

    static var virgilURL: URL? {
        resourceBundle?.url(forResource: "Virgil", withExtension: "woff2", subdirectory: "Fonts")
    }

    /// Raw bytes of the bundled hand-drawn font (embedded into exported SVGs).
    public static var handFontData: Data? { virgilURL.flatMap { try? Data(contentsOf: $0) } }

    /// Registers bundled fonts for the process (so NSTextView can use them too).
    public static func registerBundledFonts() { _ = state.handPostScriptName }

    public static func ctFont(_ family: FontFamily, size: CGFloat) -> CTFont {
        switch family {
        case .hand:
            if let name = state.handPostScriptName { return CTFontCreateWithName(name as CFString, size, nil) }
            return CTFontCreateWithName("ChalkboardSE-Regular" as CFString, size, nil)
        case .normal:
            return NSFont.systemFont(ofSize: size) as CTFont
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
        }
    }

    public static func nsFont(_ family: FontFamily, size: CGFloat) -> NSFont {
        ctFont(family, size: size) as NSFont
    }

    /// CSS font stack used in SVG export.
    public static func cssFamily(_ family: FontFamily) -> String {
        switch family {
        case .hand: "Virgil, 'Chalkboard SE', 'Comic Sans MS', cursive"
        case .normal: "-apple-system, 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif"
        case .mono: "'SF Mono', ui-monospace, Menlo, Consolas, monospace"
        }
    }
}

private final class BundleToken {}

/// Lazily registers the bundled font exactly once.
private final class FontState: Sendable {
    let handPostScriptName: String?

    init() {
        guard let url = Fonts.virgilURL else { handPostScriptName = nil; return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first else { handPostScriptName = nil; return }
        let font = CTFontCreateWithFontDescriptor(first, 12, nil)
        handPostScriptName = CTFontCopyPostScriptName(font) as String
    }
}
