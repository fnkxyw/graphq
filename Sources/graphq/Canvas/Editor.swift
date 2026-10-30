import AppKit
import Observation
import SketchCore

enum ToolKind: String, CaseIterable, Identifiable {
    case hand, selection, rectangle, diamond, ellipse, arrow, line, freedraw, text, image, eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hand: "Hand"
        case .selection: "Select"
        case .rectangle: "Rectangle"
        case .diamond: "Diamond"
        case .ellipse: "Ellipse"
        case .arrow: "Arrow"
        case .line: "Line"
        case .freedraw: "Draw"
        case .text: "Text"
        case .image: "Insert Image"
        case .eraser: "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .hand: "hand.raised"
        case .selection: "cursorarrow"
        case .rectangle: "rectangle"
        case .diamond: "diamond"
        case .ellipse: "circle"
        case .arrow: "arrow.right"
        case .line: "line.diagonal"
        case .freedraw: "pencil.and.scribble"
        case .text: "character"
        case .image: "photo"
        case .eraser: "eraser"
        }
    }

    /// Excalidraw-compatible single-key shortcut.
    var shortcut: Character? {
        switch self {
        case .hand: "h"
        case .selection: "v"
        case .rectangle: "r"
        case .diamond: "d"
        case .ellipse: "o"
        case .arrow: "a"
        case .line: "l"
        case .freedraw: "p"
        case .text: "t"
        case .image: nil
        case .eraser: "e"
        }
    }

    var elementType: ElementType? {
        switch self {
        case .rectangle: .rectangle
        case .diamond: .diamond
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .line: .line
        case .freedraw: .freedraw
        case .text: .text
        default: nil
        }
    }

    static func forKey(_ c: Character) -> ToolKind? {
        let lower = Character(c.lowercased())
        if lower == "x" { return .eraser }
        if lower == "k" { return .hand }
        return allCases.first { $0.shortcut == lower }
    }
}

/// Per-window editor state shared between the SwiftUI chrome and the AppKit canvas.
@MainActor
@Observable
final class Editor {
    let store: SceneStore

    var tool: ToolKind = .selection {
        didSet { if tool != oldValue { canvas?.toolDidChange() } }
    }
    /// Keep the current tool active after drawing (Excalidraw's "lock" button, Q).
    var toolLocked = false
    var style = StyleDefaults()
    /// Mirrors the canvas viewport zoom for the zoom indicator.
    var zoom: CGFloat = 1
    var snapToObjects = true
    var showShortcuts = false
    var showExport = false
    var isEditingText = false
    /// Becomes true after the first action; hides the empty-state hint.
    var hasInteracted = false

    @ObservationIgnored weak var canvas: CanvasView?

    init(store: SceneStore) {
        self.store = store
        self.snapToObjects = Preferences.snapToObjectsDefault
        self.style.roughness = Preferences.defaultSloppiness.rawValue
        self.style.fontFamily = Preferences.defaultFontFamily
        if store.elements.isEmpty && Preferences.gridByDefault { store.settings.gridEnabled = true }
        self.hasInteracted = !store.elements.isEmpty
    }

    func selectTool(_ t: ToolKind) {
        if t == .image {
            canvas?.insertImageFromPanel()
            return
        }
        tool = t
        hasInteracted = true
    }

    /// Called after an element was created; returns to selection unless the tool is locked.
    func finishedCreating() {
        hasInteracted = true
        if !toolLocked && tool != .freedraw && tool != .eraser { tool = .selection }
    }

    // MARK: Commands forwarded to the canvas (they need view geometry)

    func zoomIn() { canvas?.zoomStep(in: true) }
    func zoomOut() { canvas?.zoomStep(in: false) }
    func resetZoom() { canvas?.setZoom(1) }
    func zoomToFit() { canvas?.zoomToFit(selectionOnly: false) }
    func zoomToSelection() { canvas?.zoomToFit(selectionOnly: true) }
    func copyAsPNG() { canvas?.copyAsPNG() }
    func paste() { canvas?.pasteFromClipboard() }
    func copy() { canvas?.copySelection() }
}
