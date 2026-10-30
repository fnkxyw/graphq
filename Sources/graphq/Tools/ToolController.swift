import AppKit
import SketchCore

/// Pointer input already converted to scene space.
struct PointerEvent {
    var scene: CGPoint
    var view: CGPoint
    var shift: Bool
    var option: Bool
    var command: Bool
    var clickCount: Int
    /// 0...1; `nil` for devices without pressure (mouse/trackpad).
    var pressure: Double?
}

/// What tools may ask of the canvas. Keeps tools independent from CanvasView internals.
@MainActor
protocol CanvasHost: AnyObject {
    var store: SceneStore { get }
    var editor: Editor { get }
    var viewport: Viewport { get }
    /// Converts a screen-space distance to scene units at the current zoom.
    func sceneDistance(_ px: CGFloat) -> CGFloat
    /// Grid + object snapping for a single point; updates guides.
    func snap(point: CGPoint, excluding: Set<String>) -> CGPoint
    /// Object snapping for a moving box; updates guides. Returns the offset to apply.
    func snapOffset(for box: CGRect, excluding: Set<String>) -> CGPoint
    func clearGuides()
    var bindingHighlight: String? { get set }
    var fadedIds: Set<String> { get set }
    func overlayNeedsDisplay()
    func beginTextEditing(elementId: String, isNew: Bool)
    func pan(byView delta: CGPoint)
}

/// One state machine per tool.
@MainActor
protocol ToolController: AnyObject {
    func mouseDown(_ e: PointerEvent)
    func mouseDragged(_ e: PointerEvent)
    func mouseUp(_ e: PointerEvent)
    func mouseMoved(_ e: PointerEvent)
    /// Abort the current gesture (Escape, tool switch).
    func cancel()
    /// Returns true if the key was handled.
    func keyDown(_ event: NSEvent) -> Bool
    /// Tool-specific overlay in scene coordinates (context already transformed).
    func drawOverlay(in ctx: CGContext, zoom: CGFloat)
    var cursor: NSCursor { get }
}

extension ToolController {
    func mouseMoved(_ e: PointerEvent) {}
    func cancel() {}
    func keyDown(_ event: NSEvent) -> Bool { false }
    func drawOverlay(in ctx: CGContext, zoom: CGFloat) {}
    var cursor: NSCursor { .crosshair }
}

/// Builds the controller for a tool kind.
@MainActor
enum ToolFactory {
    static func make(_ kind: ToolKind, host: CanvasHost) -> ToolController {
        switch kind {
        case .selection, .image: SelectionTool(host: host)
        case .rectangle, .ellipse, .diamond: ShapeTool(host: host, type: kind.elementType!)
        case .arrow, .line: LinearTool(host: host, type: kind.elementType!)
        case .freedraw: FreedrawTool(host: host)
        case .text: TextTool(host: host)
        case .eraser: EraserTool(host: host)
        case .hand: HandTool(host: host)
        }
    }
}
