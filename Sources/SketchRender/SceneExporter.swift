import CoreGraphics
import Foundation
import ImageIO
import SketchCore
import UniformTypeIdentifiers

public struct ExportOptions: Sendable {
    public var scale: CGFloat = 2
    public var includeBackground: Bool = true
    public var darkMode: Bool = false
    public var padding: CGFloat = 16

    public init(scale: CGFloat = 2, includeBackground: Bool = true, darkMode: Bool = false, padding: CGFloat = 16) {
        self.scale = scale
        self.includeBackground = includeBackground
        self.darkMode = darkMode
        self.padding = padding
    }
}

public enum ExportError: Error, LocalizedError {
    case nothingToExport
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .nothingToExport: "There is nothing to export."
        case .renderFailed: "The image could not be rendered."
        }
    }
}

/// Raster (PNG) and vector (PDF) export through the same renderer used on screen.
public enum SceneExporter {
    /// Bounds of the exported content, including stroke slack and padding.
    public static func exportBounds(_ elements: [Element], padding: CGFloat) -> CGRect {
        let b = SceneGeometry.bounds(of: elements)
        let slack = (elements.map(\.strokeWidth).max() ?? 0) * 2 + 4
        return b.insetBy(dx: -(padding + slack), dy: -(padding + slack)).integral
    }

    public static func cgImage(_ elements: [Element], files: [String: BinaryFile], options: ExportOptions) throws -> CGImage {
        guard !elements.isEmpty else { throw ExportError.nothingToExport }
        let bounds = exportBounds(elements, padding: options.padding)
        let pw = Int((bounds.width * options.scale).rounded(.up)), ph = Int((bounds.height * options.scale).rounded(.up))
        guard pw > 0, ph > 0, pw * ph < 400_000_000,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ExportError.renderFailed }

        let theme = RenderTheme(isDark: options.darkMode)
        if options.includeBackground {
            let bg = theme.background
            ctx.setFillColor(CGColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        }
        // Flip to y-down and map scene bounds to the bitmap.
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: options.scale, y: -options.scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.setShouldSmoothFonts(false)
        let renderer = ElementRenderer(theme: theme)
        renderer.draw(elements, in: ctx, files: files)
        guard let image = ctx.makeImage() else { throw ExportError.renderFailed }
        return image
    }

    public static func png(_ elements: [Element], files: [String: BinaryFile], options: ExportOptions) throws -> Data {
        let image = try cgImage(elements, files: files, options: options)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.renderFailed
        }
        // Record the scale as DPI so 2x exports show at the correct size in viewers.
        let dpi = 72 * options.scale
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.renderFailed }
        return data as Data
    }

    public static func pdf(_ elements: [Element], files: [String: BinaryFile], options: ExportOptions) throws -> Data {
        guard !elements.isEmpty else { throw ExportError.nothingToExport }
        let bounds = exportBounds(elements, padding: options.padding)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: bounds.size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw ExportError.renderFailed }
        ctx.beginPDFPage(nil)
        let theme = RenderTheme(isDark: options.darkMode)
        if options.includeBackground {
            let bg = theme.background
            ctx.setFillColor(CGColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: 1))
            ctx.fill(mediaBox)
        }
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ElementRenderer(theme: theme).draw(elements, in: ctx, files: files)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}
