import CoreGraphics
import Foundation

public enum ExcalidrawImportError: Error, LocalizedError {
    case invalidFormat

    public var errorDescription: String? { "The file is not a valid Excalidraw drawing." }
}

/// Imports `.excalidraw` files (and Excalidraw clipboard JSON).
/// Supported: rectangle, ellipse, diamond, arrow, line, freedraw, text, image.
/// Bound text is merged into its container as a label; frames/embeds are skipped.
public enum ExcalidrawImporter {
    public static func isExcalidraw(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return false }
        return type == "excalidraw" || type == "excalidraw/clipboard"
    }

    public static func importScene(_ data: Data) throws -> SceneData {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawElements = json["elements"] as? [[String: Any]] else {
            throw ExcalidrawImportError.invalidFormat
        }
        let live = rawElements.filter { ($0["isDeleted"] as? Bool) != true }

        var elements: [Element] = []
        var labelFor: [String: [String: Any]] = [:]
        for raw in live where raw["type"] as? String == "text" {
            if let container = raw["containerId"] as? String { labelFor[container] = raw }
        }
        for raw in live {
            if raw["type"] as? String == "text", raw["containerId"] is String { continue }
            if var e = convert(raw) {
                if let label = labelFor[e.id], e.type.isContainer {
                    applyText(label, to: &e)
                }
                elements.append(e)
            }
        }
        rebind(&elements, raw: live)
        ArrowBinding.cleanup(in: &elements)

        var files: [String: BinaryFile] = [:]
        if let rawFiles = json["files"] as? [String: [String: Any]] {
            for (id, f) in rawFiles {
                guard let url = f["dataURL"] as? String, let parsed = parseDataURL(url) else { continue }
                files[id] = BinaryFile(id: id, mimeType: (f["mimeType"] as? String) ?? parsed.mime, data: parsed.data)
            }
        }
        var settings = SceneSettings()
        if let appState = json["appState"] as? [String: Any], appState["gridSize"] is NSNumber,
           (appState["gridModeEnabled"] as? Bool) == true {
            settings.gridEnabled = true
        }
        return SceneData(elements: elements, files: files, settings: settings)
    }

    // MARK: - Element conversion

    private static func num(_ v: Any?, _ fallback: Double = 0) -> Double {
        (v as? NSNumber)?.doubleValue ?? fallback
    }

    private static func color(_ v: Any?, _ fallback: RGBAColor) -> RGBAColor {
        (v as? String).flatMap(RGBAColor.init(hex:)) ?? fallback
    }

    private static func arrowhead(_ v: Any?) -> Arrowhead {
        switch v as? String {
        case "arrow": .arrow
        case "bar": .bar
        case "dot", "circle", "circle_outline": .dot
        case "triangle", "triangle_outline": .triangle
        case "diamond", "diamond_outline": .diamond
        default: .none
        }
    }

    private static func font(_ v: Any?) -> FontFamily {
        switch (v as? NSNumber)?.intValue ?? 1 {
        case 2, 6: .normal
        case 3, 8: .mono
        default: .hand
        }
    }

    private static func applyText(_ raw: [String: Any], to e: inout Element) {
        e.text = (raw["originalText"] as? String) ?? (raw["text"] as? String) ?? ""
        e.fontSize = num(raw["fontSize"], 20)
        e.fontFamily = font(raw["fontFamily"])
        e.textAlign = TextAlign(rawValue: raw["textAlign"] as? String ?? "center") ?? .center
    }

    static func convert(_ raw: [String: Any]) -> Element? {
        guard let typeName = raw["type"] as? String, let id = raw["id"] as? String else { return nil }
        let type: ElementType
        switch typeName {
        case "rectangle": type = .rectangle
        case "ellipse": type = .ellipse
        case "diamond": type = .diamond
        case "arrow": type = .arrow
        case "line": type = .line
        case "freedraw": type = .freedraw
        case "text": type = .text
        case "image": type = .image
        default: return nil
        }
        var e = Element(id: id, type: type)
        e.x = num(raw["x"]); e.y = num(raw["y"])
        e.width = num(raw["width"]); e.height = num(raw["height"])
        e.angle = num(raw["angle"])
        e.strokeColor = color(raw["strokeColor"], .ink)
        e.fillColor = color(raw["backgroundColor"], .transparent)
        e.fillStyle = FillStyle(rawValue: raw["fillStyle"] as? String ?? "hachure") ?? .hachure
        e.strokeWidth = num(raw["strokeWidth"], 2)
        e.strokeStyle = StrokeStyle(rawValue: raw["strokeStyle"] as? String ?? "solid") ?? .solid
        e.roughness = num(raw["roughness"], 1)
        e.opacity = min(1, max(0, num(raw["opacity"], 100) / 100))
        e.seed = max(1, Int(num(raw["seed"], Double(ElementID.makeSeed()))))
        e.version = Int(num(raw["version"], 1))
        e.groupIds = raw["groupIds"] as? [String] ?? []
        e.locked = raw["locked"] as? Bool ?? false

        let hasRoundness = raw["roundness"] is [String: Any]
        if hasRoundness && (type == .rectangle || type == .diamond || type == .image) {
            e.roundness = min(min(e.width, e.height) * 0.25, 32)
        }

        switch type {
        case .arrow, .line, .freedraw:
            let rawPoints = (raw["points"] as? [[Any]]) ?? []
            let pts = rawPoints.map { CGPoint(x: num($0.first), y: num($0.count > 1 ? $0[1] : nil)) }
            guard !pts.isEmpty else { return nil }
            // Excalidraw rotates linear elements around the center of their points' bbox.
            let box = CGRect(enclosing: pts)
            let center = CGPoint(x: e.x + box.midX, y: e.y + box.midY)
            let absolute = pts.map { CGPoint(x: e.x + $0.x, y: e.y + $0.y).rotated(around: center, by: e.angle) }
            e.setAbsolutePoints(absolute)
            if type == .freedraw {
                e.pressures = (raw["pressures"] as? [NSNumber])?.map(\.doubleValue) ?? []
                e.simulatePressure = raw["simulatePressure"] as? Bool ?? true
            } else {
                e.curved = hasRoundness && (raw["elbowed"] as? Bool) != true
                e.startArrowhead = arrowhead(raw["startArrowhead"])
                e.endArrowhead = type == .arrow ? arrowhead(raw["endArrowhead"]) : .none
                if type == .line { e.startArrowhead = .none }
            }
        case .text:
            applyText(raw, to: &e)
        case .image:
            e.fileId = raw["fileId"] as? String
        default:
            break
        }
        return e
    }

    /// Recreates bindings in our focus-point model from the imported endpoint positions.
    private static func rebind(_ elements: inout [Element], raw: [[String: Any]]) {
        var index: [String: Int] = [:]
        for (i, e) in elements.enumerated() { index[e.id] = i }
        for r in raw where (r["type"] as? String) == "arrow" || (r["type"] as? String) == "line" {
            guard let id = r["id"] as? String, let ai = index[id] else { continue }
            let pts = elements[ai].absolutePoints
            guard let first = pts.first, let last = pts.last else { continue }
            for (key, end, point) in [("startBinding", LinearEnd.start, first), ("endBinding", LinearEnd.end, last)] {
                guard let b = r[key] as? [String: Any], let targetId = b["elementId"] as? String,
                      let ti = index[targetId], elements[ti].type.isBindable else { continue }
                let binding = ArrowBinding.makeBinding(to: elements[ti], at: point, gap: num(b["gap"], ArrowBinding.defaultGap))
                ArrowBinding.setBinding(binding, end: end, arrowId: id, in: &elements, index: index)
            }
        }
    }

    static func parseDataURL(_ s: String) -> (mime: String, data: Data)? {
        guard s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") else { return nil }
        let header = s[s.index(s.startIndex, offsetBy: 5)..<comma]
        let mime = header.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        guard header.contains("base64"), let data = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return (mime, data)
    }
}
