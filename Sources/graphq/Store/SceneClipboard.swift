import AppKit
import SketchCore
import SketchRender
import UniformTypeIdentifiers

/// Clipboard I/O. Elements travel as a `.graphq` JSON payload under a private
/// type (works across documents and app instances), plus a PNG and plain-text
/// representation so other apps get something sensible.
enum SceneClipboard {
    static let elementsType = NSPasteboard.PasteboardType("app.graphq.elements")

    enum Content {
        case scene(SceneData)
        case image(Data, mimeType: String)
        case text(String)
    }

    static func write(_ elements: [Element], files: [String: BinaryFile], includePNG: Bool = true) {
        let scene = SceneData(elements: elements, files: files)
        guard let json = try? DocumentCodec.encode(scene) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        var types: [NSPasteboard.PasteboardType] = [elementsType]
        if includePNG { types.append(.png) }
        pb.declareTypes(types, owner: nil)
        pb.setData(json, forType: elementsType)
        if includePNG, let png = try? SceneExporter.png(elements, files: files, options: ExportOptions(scale: 2)) {
            pb.setData(png, forType: .png)
        }
    }

    static func writePNG(_ elements: [Element], files: [String: BinaryFile], darkMode: Bool) throws {
        let png = try SceneExporter.png(elements, files: files,
                                        options: ExportOptions(scale: 2, includeBackground: true, darkMode: darkMode))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    static func read() -> Content? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: elementsType), let scene = try? DocumentCodec.decode(data) {
            return .scene(scene)
        }
        for (type, mime) in [(NSPasteboard.PasteboardType.png, "image/png"),
                             (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "image/jpeg")] {
            if let data = pb.data(forType: type) { return .image(data, mimeType: mime) }
        }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return .image(png, mimeType: "image/png")
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let image = ImageImport.load(url) {
            return .image(image.data, mimeType: image.mimeType)
        }
        if let string = pb.string(forType: .string), !string.isEmpty {
            if let data = string.data(using: .utf8), ExcalidrawImporter.isExcalidraw(data),
               let scene = try? ExcalidrawImporter.importScene(data) {
                return .scene(scene)
            }
            return .text(string)
        }
        return nil
    }
}

enum ImageImport {
    static let supportedTypes: [UTType] = [.png, .jpeg, .gif, .tiff, .heic, .webP, .bmp]

    /// Loads an image file; formats other than PNG/JPEG/GIF are converted to PNG.
    static func load(_ url: URL) -> (data: Data, mimeType: String)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        if type == .png { return (data, "image/png") }
        if type == .jpeg { return (data, "image/jpeg") }
        if type == .gif { return (data, "image/gif") }
        guard let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return (png, "image/png")
    }

    /// Pixel size of encoded image data.
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        return CGSize(width: w, height: h)
    }
}
