import CoreGraphics
import Foundation
import Testing
@testable import SketchCore

// MARK: - Rough engine

@Suite("Rough generator")
struct RoughTests {
    @Test func randomIsDeterministic() {
        var a = RoughRandom(seed: 42), b = RoughRandom(seed: 42)
        for _ in 0..<100 { #expect(a.next() == b.next()) }
        var c = RoughRandom(seed: 43)
        #expect(RoughRandom(seed: 42).nextValue != c.next())
    }

    @Test func sameSeedSameOps() {
        let e = Element(type: .rectangle, width: 120, height: 80, fillColor: .white, seed: 7)
        let a = ShapeBuilder.build(e).flatMap(\.ops)
        let b = ShapeBuilder.build(e).flatMap(\.ops)
        #expect(a == b)
        var other = e
        other.seed = 8
        #expect(ShapeBuilder.build(other).flatMap(\.ops) != a)
    }

    @Test func architectLinesAreStraight() {
        var o = RoughOptions()
        o.roughness = 0
        let ops = RoughGenerator(options: o).line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        for op in ops {
            switch op {
            case .move(let p), .line(let p): #expect(abs(p.y) < 1e-9)
            case .curve(let c1, let c2, let p): #expect(abs(c1.y) + abs(c2.y) + abs(p.y) < 1e-9)
            }
        }
    }

    @Test func multiStrokeDoublesLines() {
        var o = RoughOptions()
        let double = RoughGenerator(options: o).line(.zero, CGPoint(x: 50, y: 50))
        o.disableMultiStroke = true
        let single = RoughGenerator(options: o).line(.zero, CGPoint(x: 50, y: 50))
        #expect(double.count == single.count * 2)
    }

    @Test func hachureCoversSquare() {
        let square = CGRect(x: 0, y: 0, width: 100, height: 100).corners
        let lines = Hachure.lines(polygon: square, angle: 0, gap: 10)
        #expect(lines.count >= 9 && lines.count <= 11)
        for (a, b) in lines {
            #expect(a.x >= -1 && b.x <= 101)
        }
    }

    @Test func roughPointsStayNearShape() {
        let e = Element(type: .ellipse, width: 200, height: 100, roughness: 2, seed: 99)
        for item in ShapeBuilder.build(e) {
            for op in item.ops {
                if case .move(let p) = op {
                    #expect(CGRect(x: -20, y: -20, width: 240, height: 140).contains(p))
                }
            }
        }
    }
}

private extension RoughRandom {
    var nextValue: Double { var c = self; return c.next() }
}

// MARK: - Freehand

@Suite("Freehand")
struct FreehandTests {
    @Test func outlineIsClosedPolygonAroundStroke() {
        let pts = (0..<30).map { CGPoint(x: Double($0) * 5, y: 0) }
        let outline = Freehand.outline(points: pts, pressures: [], options: .init(size: 8))
        #expect(outline.count > 10)
        let box = CGRect(enclosing: outline)
        #expect(box.height > 3 && box.height < 20)
        #expect(box.minX < 2 && box.maxX > 140)
    }

    @Test func singlePointMakesDot() {
        let outline = Freehand.outline(points: [CGPoint(x: 10, y: 10)], pressures: [], options: .init(size: 8))
        #expect(!outline.isEmpty)
    }
}

// MARK: - Geometry

@Suite("Geometry")
struct GeometryTests {
    @Test func localSceneRoundTripWithRotation() {
        let e = Element(type: .rectangle, x: 10, y: 20, width: 100, height: 50, angle: 0.7)
        let p = CGPoint(x: 33, y: 12)
        let back = e.toLocal(e.toScene(p))
        #expect(back.distance(to: p) < 1e-9)
    }

    @Test func setAbsolutePointsKeepsPositions() {
        var e = Element(type: .line, angle: 0.5)
        let pts = [CGPoint(x: 10, y: 10), CGPoint(x: 80, y: 40), CGPoint(x: 20, y: 90)]
        e.setAbsolutePoints(pts)
        for (a, b) in zip(e.absolutePoints, pts) { #expect(a.distance(to: b) < 1e-9) }
        #expect(e.points.map(\.x).min()! >= -1e-9)
        #expect(e.points.map(\.y).min()! >= -1e-9)
    }

    @Test func hitTestRespectsFill() {
        var e = Element(type: .rectangle, x: 0, y: 0, width: 100, height: 100)
        #expect(!HitTest.hits(e, CGPoint(x: 50, y: 50), tolerance: 2))
        #expect(HitTest.hits(e, CGPoint(x: 0, y: 50), tolerance: 2))
        e.fillColor = .white
        #expect(HitTest.hits(e, CGPoint(x: 50, y: 50), tolerance: 2))
    }

    @Test func hitTestRotatedShape() {
        let e = Element(type: .rectangle, x: 0, y: 0, width: 200, height: 20, angle: .pi / 2, fillColor: .white)
        // Rotated 90° around (100, 10): now a vertical bar at x≈100.
        #expect(HitTest.hits(e, CGPoint(x: 100, y: 80), tolerance: 1))
        #expect(!HitTest.hits(e, CGPoint(x: 180, y: 10), tolerance: 1))
    }

    @Test func hitTestLinear() {
        var e = Element(type: .arrow)
        e.setAbsolutePoints([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
        #expect(HitTest.hits(e, CGPoint(x: 50, y: 51), tolerance: 3))
        #expect(!HitTest.hits(e, CGPoint(x: 50, y: 80), tolerance: 3))
    }

    @Test func ellipseIntersection() {
        let e = Element(type: .ellipse, x: 0, y: 0, width: 100, height: 100)
        let hit = Intersections.outline(of: e, from: CGPoint(x: -100, y: 50), to: CGPoint(x: 50, y: 50))
        #expect(hit != nil)
        #expect(abs(hit!.x - 0) < 1e-6)
    }

    @Test func rectangleIntersectionRotated() {
        let e = Element(type: .rectangle, x: 0, y: 0, width: 100, height: 100, angle: .pi / 4)
        let hit = Intersections.outline(of: e, from: CGPoint(x: -200, y: 50), to: CGPoint(x: 50, y: 50))!
        // A diamond-oriented square of side 100 reaches 50·√2 from its center.
        #expect(abs(hit.x - (50 - 50 * 2.0.squareRoot())) < 0.5)
    }

    @Test func spatialIndexQueries() {
        var idx = SpatialIndex(cellSize: 50)
        idx.insert("a", rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        idx.insert("b", rect: CGRect(x: 500, y: 500, width: 10, height: 10))
        idx.insert("huge", rect: CGRect(x: -1e5, y: -1e5, width: 2e5, height: 2e5))
        #expect(idx.query(CGRect(x: -5, y: -5, width: 20, height: 20)) == ["a", "huge"])
        idx.insert("a", rect: CGRect(x: 1000, y: 1000, width: 5, height: 5))
        #expect(!idx.query(CGRect(x: -5, y: -5, width: 20, height: 20)).contains("a"))
        idx.remove("b")
        #expect(!idx.query(CGRect(x: 490, y: 490, width: 30, height: 30)).contains("b"))
    }

    @Test func snappingAlignsEdges() {
        let moving = CGRect(x: 103, y: 300, width: 50, height: 50)
        let r = Snapping.snap(moving, to: [CGRect(x: 100, y: 0, width: 80, height: 40)], threshold: 5)
        #expect(r.offset.x == -3)
        #expect(r.offset.y == 0)
        #expect(!r.guides.isEmpty)
    }

    @Test func alignAndDistribute() {
        let boxes = [CGRect(x: 0, y: 0, width: 10, height: 10),
                     CGRect(x: 50, y: 20, width: 10, height: 10),
                     CGRect(x: 200, y: 5, width: 10, height: 10)]
        #expect(Alignment.align(boxes, .left).map(\.x) == [0, -50, -200])
        #expect(Alignment.align(boxes, .top).map(\.y) == [0, -20, -5])
        let d = Alignment.distribute(boxes, .horizontal)
        #expect(d[0] == .zero && d[2] == .zero)
        #expect(abs((50 + d[1].x) - 100) < 1e-9)
    }
}

// MARK: - Transforms

@Suite("Transforms")
struct TransformTests {
    @Test func cornerResizeKeepsOppositeCorner() {
        let e = Element(type: .rectangle, x: 0, y: 0, width: 100, height: 50)
        let n = Transforms.resize(e, handle: .se, pointer: CGPoint(x: 200, y: 150), keepAspect: false, fromCenter: false)
        #expect(n.rect == CGRect(x: 0, y: 0, width: 200, height: 150))
    }

    @Test func resizeRotatedKeepsAnchorOnScreen() {
        let e = Element(type: .rectangle, x: 0, y: 0, width: 100, height: 50, angle: 0.6)
        let anchorBefore = e.toScene(CGPoint(x: 0, y: 0)) // nw corner is the anchor of se
        let n = Transforms.resize(e, handle: .se, pointer: e.toScene(CGPoint(x: 150, y: 90)), keepAspect: false, fromCenter: false)
        #expect(n.toScene(CGPoint(x: 0, y: 0)).distance(to: anchorBefore) < 1e-6)
        #expect(abs(n.width - 150) < 1e-6 && abs(n.height - 90) < 1e-6)
    }

    @Test func aspectLock() {
        let e = Element(type: .rectangle, width: 100, height: 50)
        let n = Transforms.resize(e, handle: .se, pointer: CGPoint(x: 300, y: 60), keepAspect: true, fromCenter: false)
        #expect(abs(n.width / n.height - 2) < 1e-9)
    }

    @Test func flipThroughAnchor() {
        let e = Element(type: .rectangle, x: 0, y: 0, width: 100, height: 100)
        let n = Transforms.resize(e, handle: .e, pointer: CGPoint(x: -50, y: 50), keepAspect: false, fromCenter: false)
        #expect(n.rect == CGRect(x: -50, y: 0, width: 50, height: 100))
    }

    @Test func groupResizeScalesPositions() {
        let a = Element(type: .rectangle, x: 0, y: 0, width: 10, height: 10)
        let b = Element(type: .rectangle, x: 90, y: 90, width: 10, height: 10)
        let out = Transforms.resize([a, b], bounds: CGRect(x: 0, y: 0, width: 100, height: 100), handle: .se,
                                    pointer: CGPoint(x: 200, y: 200), keepAspect: false, fromCenter: false)
        #expect(out[1].rect == CGRect(x: 180, y: 180, width: 20, height: 20))
    }

    @Test func rotationAroundCenterIsRigid() {
        let a = Element(type: .rectangle, x: 0, y: 0, width: 10, height: 10)
        let out = Transforms.rotate([a], around: CGPoint(x: 50, y: 5), by: .pi)
        #expect(out[0].center.distance(to: CGPoint(x: 95, y: 5)) < 1e-9)
        #expect(abs(out[0].angle - .pi) < 1e-9)
    }
}

// MARK: - Binding

@Suite("Arrow binding")
struct BindingTests {
    private func scene() -> ([Element], [String: Int]) {
        let box = Element(id: "box", type: .rectangle, x: 200, y: 0, width: 100, height: 100)
        var arrow = Element(id: "arrow", type: .arrow)
        arrow.setAbsolutePoints([CGPoint(x: 0, y: 50), CGPoint(x: 250, y: 50)])
        var els = [box, arrow]
        let index = ["box": 0, "arrow": 1]
        let b = ArrowBinding.makeBinding(to: els[0], at: CGPoint(x: 250, y: 50))
        ArrowBinding.setBinding(b, end: .end, arrowId: "arrow", in: &els, index: index)
        ArrowBinding.updateArrows(boundTo: ["box"], in: &els, index: index)
        return (els, index)
    }

    @Test func arrowStopsAtOutlineWithGap() {
        let (els, _) = scene()
        let end = els[1].absolutePoints.last!
        #expect(abs(end.x - (200 - ArrowBinding.defaultGap)) < 0.01)
        #expect(abs(end.y - 50) < 0.01)
        #expect(els[0].boundElements == ["arrow"])
    }

    @Test func arrowFollowsMovedShape() {
        var (els, index) = scene()
        els[0].move(by: CGPoint(x: 100, y: 200))
        ArrowBinding.updateArrows(boundTo: ["box"], in: &els, index: index)
        let end = els[1].absolutePoints.last!
        #expect(HitTest.isInside(els[0], end, padding: ArrowBinding.defaultGap + 1))
        #expect(!HitTest.isInside(els[0], end))
        #expect(els[1].absolutePoints.first!.distance(to: CGPoint(x: 0, y: 50)) < 1e-6)
    }

    @Test func cleanupRemovesDanglingBindings() {
        var (els, _) = scene()
        els.removeFirst()
        ArrowBinding.cleanup(in: &els)
        #expect(els[0].endBinding == nil)
    }
}

// MARK: - Groups

@Suite("Groups")
struct GroupTests {
    @Test func expandSelectsWholeGroup() {
        let a = Element(id: "a", type: .rectangle, groupIds: ["g"])
        let b = Element(id: "b", type: .rectangle, groupIds: ["g"])
        let c = Element(id: "c", type: .rectangle)
        #expect(Groups.expand(["a"], in: [a, b, c], editingGroupId: nil) == ["a", "b"])
        #expect(Groups.expand(["a"], in: [a, b, c], editingGroupId: "g") == ["a"])
    }

    @Test func duplicateRemapsIdsGroupsAndBindings() {
        let box = Element(id: "box", type: .rectangle, groupIds: ["g"], boundElements: ["arr"])
        var arr = Element(id: "arr", type: .arrow, groupIds: ["g"])
        arr.endBinding = PointBinding(elementId: "box", focus: CGPoint(x: 0.5, y: 0.5), gap: 4)
        let copies = Groups.duplicate([box, arr], offset: CGPoint(x: 10, y: 10))
        #expect(Set(copies.map(\.id)).isDisjoint(with: ["box", "arr"]))
        #expect(copies[0].groupIds == copies[1].groupIds && copies[0].groupIds != ["g"])
        #expect(copies[1].endBinding?.elementId == copies[0].id)
        #expect(copies[0].boundElements == [copies[1].id])
        #expect(copies[0].x == 10)
    }
}

// MARK: - IO

@Suite("Document IO")
struct IOTests {
    @Test func roundTrip() throws {
        var line = Element(type: .arrow, startArrowhead: .dot, endArrowhead: .triangle, curved: true)
        line.setAbsolutePoints([CGPoint(x: 1, y: 2), CGPoint(x: 30, y: 40), CGPoint(x: 70, y: 10)])
        let scene = SceneData(
            elements: [Element(type: .rectangle, x: 1, y: 2, width: 3, height: 4, text: "Hi"), line,
                       Element(type: .image, fileId: "f1")],
            files: ["f1": BinaryFile(id: "f1", mimeType: "image/png", data: Data([1, 2, 3])),
                    "unused": BinaryFile(id: "unused", mimeType: "image/png", data: Data([9]))],
            settings: SceneSettings(gridEnabled: true))
        let decoded = try DocumentCodec.decode(try DocumentCodec.encode(scene))
        #expect(decoded.elements == scene.elements)
        #expect(decoded.files.keys.sorted() == ["f1"])
        #expect(decoded.settings.gridEnabled)
    }

    @Test func versioning() throws {
        let future = #"{"type":"graphq","schemaVersion":999,"elements":[],"files":{}}"#
        #expect(throws: DocumentCodecError.unsupportedVersion(999)) { try DocumentCodec.decode(Data(future.utf8)) }
        let legacy = #"{"type":"sketchboard","elements":[{"id":"x","type":"ellipse"}]}"#
        let s = try DocumentCodec.decode(Data(legacy.utf8))
        #expect(s.elements.first?.type == .ellipse)
        #expect(throws: DocumentCodecError.notAGraphqFile) {
            try DocumentCodec.decode(Data(#"{"type":"excalidraw"}"#.utf8))
        }
    }

    @Test func colorHex() {
        #expect(RGBAColor(hex: "#ff0000") == RGBAColor(r: 1, g: 0, b: 0))
        #expect(RGBAColor(hex: "#f00")?.hexString == "#ff0000")
        #expect(RGBAColor(hex: "transparent")?.isTransparent == true)
        #expect(RGBAColor(hex: "#00000080")!.a > 0.49)
    }

    @Test func darkModeInversionKeepsHue() {
        let ink = RGBAColor.ink.adaptedForDarkMode()
        #expect(ink.hsl.l > 0.8)
        let red = RGBAColor(hex: "#d64545")!
        let adapted = red.adaptedForDarkMode()
        #expect(abs(adapted.hsl.h - red.hsl.h) < 0.01)
        let pastel = RGBAColor(hex: "#d7e5ff")!.adaptedForDarkMode()
        #expect(pastel.hsl.l < 0.4)
    }

    @Test func excalidrawImport() throws {
        let json = """
        {"type":"excalidraw","version":2,"elements":[
          {"id":"r1","type":"rectangle","x":10,"y":20,"width":100,"height":60,"angle":0,"strokeColor":"#1e1e1e",
           "backgroundColor":"#a5d8ff","fillStyle":"cross-hatch","strokeWidth":2,"strokeStyle":"dashed","roughness":1,
           "opacity":80,"groupIds":[],"roundness":{"type":3},"seed":123,"version":3,"isDeleted":false,"locked":false,
           "boundElements":[{"type":"text","id":"t1"},{"type":"arrow","id":"a1"}]},
          {"id":"t1","type":"text","x":20,"y":40,"width":50,"height":25,"text":"Box","originalText":"Box","fontSize":20,
           "fontFamily":1,"textAlign":"center","containerId":"r1"},
          {"id":"a1","type":"arrow","x":-100,"y":50,"width":104,"height":0,"points":[[0,0],[104,0]],
           "endBinding":{"elementId":"r1","focus":0,"gap":6},"startArrowhead":null,"endArrowhead":"arrow","roundness":null},
          {"id":"d","type":"diamond","x":0,"y":0,"width":10,"height":10,"isDeleted":true},
          {"id":"f","type":"frame","x":0,"y":0,"width":10,"height":10}
        ],"files":{}}
        """
        let scene = try ExcalidrawImporter.importScene(Data(json.utf8))
        #expect(scene.elements.map(\.id) == ["r1", "a1"])
        let rect = scene.elements[0]
        #expect(rect.text == "Box")
        #expect(rect.fillStyle == .crossHatch)
        #expect(rect.strokeStyle == .dashed)
        #expect(abs(rect.opacity - 0.8) < 1e-9)
        #expect(rect.roundness > 0)
        #expect(rect.boundElements == ["a1"])
        let arrow = scene.elements[1]
        #expect(arrow.endBinding?.elementId == "r1")
        #expect(arrow.endArrowhead == .arrow && arrow.startArrowhead == .none)
        #expect(arrow.absolutePoints.last!.distance(to: CGPoint(x: 4, y: 50)) < 1e-6)
    }
}
