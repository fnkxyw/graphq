import CoreGraphics
import Foundation

/// Writes scenes as `.excalidraw` JSON (schema version 2), so drawings can be opened
/// on excalidraw.com. Labels become bound text elements, as Excalidraw expects.
public enum ExcalidrawExporter {
    /// Measures text (provided by the render layer; Core has no font access).
    public typealias Measure = (_ text: String, _ family: FontFamily, _ fontSize: Double) -> CGSize

    public static func export(_ scene: SceneData, source: String = "https://github.com/fnkxyw/graphq",
                              measure: Measure) throws -> Data {
        var out: [[String: Any]] = []
        let now = Int(Date().timeIntervalSince1970 * 1000)
        for e in scene.elements {
            var labelId: String?
            if !e.text.isEmpty && (e.type.isContainer || e.type.isLinear) { labelId = "\(e.id)-label" }
            out.append(element(e, labelId: labelId, updated: now))
            if let labelId { out.append(label(for: e, id: labelId, measure: measure, updated: now)) }
        }
        var files: [String: Any] = [:]
        for (id, f) in scene.prunedFiles() {
            files[id] = [
                "id": id, "mimeType": f.mimeType, "created": now,
                "dataURL": "data:\(f.mimeType);base64,\(f.data.base64EncodedString())",
            ]
        }
        let json: [String: Any] = [
            "type": "excalidraw", "version": 2, "source": source,
            "elements": out,
            "appState": ["viewBackgroundColor": "#ffffff", "gridSize": scene.settings.gridEnabled ? 20 as Any : NSNull() as Any],
            "files": files,
        ]
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    private static func color(_ c: RGBAColor) -> String {
        c.isTransparent ? "transparent" : c.withAlpha(1).hexString
    }

    private static func arrowhead(_ a: Arrowhead) -> Any {
        switch a {
        case .none: NSNull()
        case .arrow: "arrow"
        case .triangle: "triangle"
        case .dot: "dot"
        case .bar: "bar"
        case .diamond: "diamond"
        }
    }

    private static func fontFamily(_ f: FontFamily) -> Int {
        switch f {
        case .hand: 1
        case .normal: 2
        case .mono: 3
        }
    }

    private static func element(_ e: Element, labelId: String?, updated: Int) -> [String: Any] {
        var d: [String: Any] = [
            "id": e.id, "type": e.type.rawValue,
            "x": e.x, "y": e.y, "width": e.width, "height": e.height, "angle": e.angle,
            "strokeColor": color(e.strokeColor), "backgroundColor": color(e.fillColor),
            "fillStyle": e.fillStyle.rawValue, "strokeWidth": e.strokeWidth,
            "strokeStyle": e.strokeStyle.rawValue, "roughness": e.roughness,
            "opacity": Int((e.opacity * 100).rounded()),
            "groupIds": e.groupIds, "frameId": e.frameId ?? NSNull(),
            "seed": e.seed, "version": e.version, "versionNonce": e.versionNonce,
            "isDeleted": false, "updated": updated, "link": NSNull(), "locked": e.locked,
            "index": NSNull(),
        ]
        var bound: [[String: String]] = e.boundElements.map { ["id": $0, "type": "arrow"] }
        if let labelId { bound.append(["id": labelId, "type": "text"]) }
        d["boundElements"] = bound.isEmpty ? NSNull() : bound

        switch e.type {
        case .rectangle, .diamond, .image:
            d["roundness"] = e.roundness > 0 ? ["type": 3] : NSNull()
        case .arrow, .line:
            d["roundness"] = e.curved ? ["type": 2] : NSNull()
        default:
            d["roundness"] = NSNull()
        }

        switch e.type {
        case .arrow, .line, .freedraw:
            // Our points are relative to the bbox origin (x, y): exactly what Excalidraw expects.
            d["points"] = e.points.map { [$0.x, $0.y] }
            d["lastCommittedPoint"] = NSNull()
            if e.type == .freedraw {
                d["pressures"] = e.pressures
                d["simulatePressure"] = e.simulatePressure
            } else {
                d["startBinding"] = e.startBinding.map { binding($0) } ?? NSNull()
                d["endBinding"] = e.endBinding.map { binding($0) } ?? NSNull()
                d["startArrowhead"] = arrowhead(e.startArrowhead)
                d["endArrowhead"] = e.type == .arrow ? arrowhead(e.endArrowhead) : NSNull()
                // Exported as a plain polyline: Excalidraw's elbow format needs its own routing data.
                d["elbowed"] = false
            }
        case .text:
            d["text"] = e.text
            d["originalText"] = e.text
            d["fontSize"] = e.fontSize
            d["fontFamily"] = fontFamily(e.fontFamily)
            d["textAlign"] = e.textAlign.rawValue
            d["verticalAlign"] = "top"
            d["containerId"] = NSNull()
            d["lineHeight"] = 1.25
            d["autoResize"] = true
        case .image:
            d["fileId"] = e.fileId ?? NSNull()
            d["status"] = "saved"
            d["scale"] = [1, 1]
        case .frame:
            d["name"] = e.text.isEmpty ? NSNull() : e.text
        default:
            break
        }
        return d
    }

    private static func binding(_ b: PointBinding) -> [String: Any] {
        ["elementId": b.elementId, "focus": 0, "gap": b.gap]
    }

    private static func label(for e: Element, id: String, measure: Measure, updated: Int) -> [String: Any] {
        let size = measure(e.text, e.fontFamily, e.fontSize)
        let center = e.type.isLinear ? e.toScene(e.labelAnchor) : e.center
        return [
            "id": id, "type": "text",
            "x": center.x - size.width / 2, "y": center.y - size.height / 2,
            "width": size.width, "height": size.height, "angle": e.type.isLinear ? 0 : e.angle,
            "strokeColor": color(e.strokeColor), "backgroundColor": "transparent",
            "fillStyle": "solid", "strokeWidth": 1, "strokeStyle": "solid", "roughness": 1, "opacity": Int((e.opacity * 100).rounded()),
            "groupIds": e.groupIds, "frameId": e.frameId ?? NSNull(), "roundness": NSNull(),
            "seed": e.seed &+ 1, "version": 1, "versionNonce": e.versionNonce &+ 1,
            "isDeleted": false, "boundElements": NSNull(), "updated": updated, "link": NSNull(), "locked": e.locked,
            "text": e.text, "originalText": e.text, "fontSize": e.fontSize, "fontFamily": fontFamily(e.fontFamily),
            "textAlign": e.type.isLinear ? "center" : e.textAlign.rawValue, "verticalAlign": "middle",
            "containerId": e.id, "lineHeight": 1.25, "autoResize": true, "index": NSNull(),
        ]
    }
}
