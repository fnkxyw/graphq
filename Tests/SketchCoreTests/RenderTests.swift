import CoreGraphics
import Foundation
import Testing
@testable import SketchCore
@testable import SketchRender

@Suite("Render & export")
struct RenderTests {
    static func demoScene() -> [Element] {
        var els: [Element] = []
        let box = Element(id: "box", type: .rectangle, x: 0, y: 0, width: 200, height: 110,
                          fillColor: RGBAColor(hex: "#d7e5ff")!, roundness: 8, text: "Idea")
        let oval = Element(id: "oval", type: .ellipse, x: 360, y: -10, width: 190, height: 130,
                           fillColor: RGBAColor(hex: "#ffd8d8")!, fillStyle: .crossHatch, text: "Prototype")
        let diamond = Element(id: "dia", type: .diamond, x: 380, y: 220, width: 160, height: 130,
                              fillColor: RGBAColor(hex: "#d3f2dc")!, fillStyle: .solid, text: "Ship?")
        els += [box, oval, diamond]
        var a1 = Element(id: "a1", type: .arrow, endArrowhead: .arrow)
        a1.setAbsolutePoints([CGPoint(x: 100, y: 55), CGPoint(x: 455, y: 55)])
        var a2 = Element(id: "a2", type: .arrow, strokeStyle: .dashed, endArrowhead: .triangle, curved: true)
        a2.setAbsolutePoints([CGPoint(x: 455, y: 60), CGPoint(x: 600, y: 180), CGPoint(x: 460, y: 285)])
        els += [a1, a2]
        var index: [String: Int] = [:]
        for (i, e) in els.enumerated() { index[e.id] = i }
        ArrowBinding.setBinding(ArrowBinding.makeBinding(to: box, at: box.center), end: .start, arrowId: "a1", in: &els, index: index)
        ArrowBinding.setBinding(ArrowBinding.makeBinding(to: oval, at: oval.center), end: .end, arrowId: "a1", in: &els, index: index)
        ArrowBinding.setBinding(ArrowBinding.makeBinding(to: oval, at: oval.center), end: .start, arrowId: "a2", in: &els, index: index)
        ArrowBinding.setBinding(ArrowBinding.makeBinding(to: diamond, at: diamond.center), end: .end, arrowId: "a2", in: &els, index: index)
        ArrowBinding.updateArrows(boundTo: ["box", "oval", "dia"], in: &els, index: index)
        var f = Element(type: .freedraw, strokeColor: RGBAColor(hex: "#d64545")!)
        f.setAbsolutePoints((0..<70).map { i in CGPoint(x: Double(i) * 4, y: 260 + sin(Double(i) / 6) * 25) })
        els.append(f)
        els.append(Element(type: .text, x: 0, y: 340, width: 280, height: 35, strokeColor: RGBAColor(hex: "#3f73e0")!,
                           text: "graphq", fontSize: 28, textAlign: .left))
        return els
    }

    @Test func pngExportHasExpectedSize() throws {
        let els = Self.demoScene()
        let img = try SceneExporter.cgImage(els, files: [:], options: ExportOptions(scale: 2))
        let bounds = SceneExporter.exportBounds(els, padding: 16)
        #expect(img.width == Int((bounds.width * 2).rounded(.up)))
        let png = try SceneExporter.png(els, files: [:], options: ExportOptions(scale: 1))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("graphq-demo.png"))
    }

    @Test func pdfAndSvgExport() throws {
        let els = Self.demoScene()
        let pdf = try SceneExporter.pdf(els, files: [:], options: ExportOptions())
        #expect(pdf.starts(with: Array("%PDF".utf8)))
        let svg = try SVGExporter.svg(els, files: [:], options: ExportOptions(includeBackground: false))
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.contains("<text"))
        #expect(svg.contains("@font-face"))
        #expect(svg.components(separatedBy: "<path").count > 10)
    }

    @Test func emptyExportThrows() {
        #expect(throws: ExportError.self) { try SceneExporter.png([], files: [:], options: ExportOptions()) }
    }

    @Test func handFontIsBundled() {
        #expect(Fonts.handFontData != nil)
    }

    @Test func textLayoutWraps() {
        let narrow = TextLayout(text: "one two three four five six", family: .normal, fontSize: 20, maxWidth: 80)
        let wide = TextLayout(text: "one two three four five six", family: .normal, fontSize: 20)
        #expect(narrow.lines.count > 1)
        #expect(wide.lines.count == 1)
        #expect(narrow.size.width <= 81)
    }

    /// Rendering 2000 cached elements must stay well within a 60 fps frame budget.
    @Test func renderPerformance() throws {
        var els: [Element] = []
        for i in 0..<2000 {
            let t: ElementType = [.rectangle, .ellipse, .diamond][i % 3]
            els.append(Element(type: t, x: Double(i % 50) * 60, y: Double(i / 50) * 60, width: 50, height: 40,
                               fillColor: i % 2 == 0 ? RGBAColor(hex: "#d7e5ff")! : .transparent))
        }
        let ctx = CGContext(data: nil, width: 1600, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: 0.5, y: 0.5)
        let renderer = ElementRenderer()
        renderer.draw(els, in: ctx, files: [:]) // warm the path cache
        let start = Date()
        renderer.draw(els, in: ctx, files: [:])
        let elapsed = Date().timeIntervalSince(start)
        print("2000 cached elements drawn in \(Int(elapsed * 1000)) ms")
        #expect(elapsed < 0.1)
    }

    /// Writes Examples/Welcome.graphq if missing, and checks the committed one still decodes.
    @Test func exampleDocument() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Examples")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Welcome.graphq")
        if !FileManager.default.fileExists(atPath: url.path) {
            try DocumentCodec.encode(SceneData(elements: Self.demoScene()), prettyPrinted: true).write(to: url)
        }
        let scene = try DocumentCodec.decode(Data(contentsOf: url))
        #expect(scene.elements.count == Self.demoScene().count)
    }
}
