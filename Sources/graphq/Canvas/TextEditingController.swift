import AppKit
import SketchCore
import SketchRender

/// In-place text editing: an NSTextView laid over the element, styled to match the
/// rendered text at the current zoom. The element updates live while typing.
@MainActor
final class TextEditingController: NSObject, NSTextViewDelegate {
    let elementId: String
    let isNew: Bool
    let textView: NSTextView
    private unowned let canvas: CanvasView
    /// Typing undo stays local to the editor so it never mixes with document history.
    private let localUndo = UndoManager()

    init(canvas: CanvasView, elementId: String, isNew: Bool) {
        self.canvas = canvas
        self.elementId = elementId
        self.isNew = isNew
        textView = NSTextView(frame: .zero)
        super.init()

        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.delegate = self
        textView.string = canvas.store.element(elementId)?.text ?? ""
        canvas.addSubview(textView)
        layout()
        canvas.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    private var element: Element? { canvas.store.element(elementId) }

    /// Positions and styles the text view to sit exactly over the rendered text.
    func layout() {
        guard let e = element else { return }
        let zoom = canvas.viewport.zoom
        let isFrame = e.type == .frame
        let fontSize = (isFrame ? 13 : e.fontSize) * zoom
        let font = Fonts.nsFont(isFrame ? .normal : e.fontFamily, size: fontSize)
        let lineHeight = fontSize * TextLayout.lineHeightFactor

        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight
        let align: NSTextAlignment = switch e.textAlign {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        para.alignment = e.type.isLinear ? .center : isFrame ? .left : align
        // Arrow labels sit on a knockout so the line doesn't show through while typing.
        textView.drawsBackground = e.type.isLinear
        let bg = canvas.renderer.theme.background
        textView.backgroundColor = NSColor(srgbRed: bg.r, green: bg.g, blue: bg.b, alpha: 1)
        let color = NSColor(cgColor: canvas.renderer.cgColor(e.strokeColor)) ?? .labelColor
        // TextKit puts extra line height above the glyphs; shift them to match the renderer.
        let baselineShift = (lineHeight - (font.ascender - font.descender)) / 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: para, .foregroundColor: color, .baselineOffset: baselineShift,
        ]
        textView.typingAttributes = attrs
        textView.defaultParagraphStyle = para
        textView.insertionPointColor = color
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }

        let frame: CGRect
        if isFrame {
            let origin = canvas.viewport.toView(CGPoint(x: e.x + 2, y: e.y - Element.frameTitleHeight + 2))
            frame = CGRect(x: origin.x, y: origin.y, width: max(e.width * zoom, 120), height: lineHeight)
            textView.textContainer?.size = CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        } else if e.type.isLinear {
            let size = TextMetrics.measure(textView.string, family: e.fontFamily, fontSize: e.fontSize)
            let anchor = canvas.viewport.toView(e.toScene(e.labelAnchor))
            let w = max(size.width * zoom, 20) + fontSize
            frame = CGRect(x: anchor.x - w / 2, y: anchor.y - size.height * zoom / 2, width: w, height: size.height * zoom)
            textView.textContainer?.size = CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        } else if e.type == .text {
            let size = TextMetrics.measure(textView.string, family: e.fontFamily, fontSize: e.fontSize)
            let origin = canvas.viewport.toView(CGPoint(x: e.x, y: e.y))
            // Leave room for the caret at the end of the longest line.
            frame = CGRect(x: origin.x, y: origin.y, width: max(size.width * zoom, 4) + fontSize, height: size.height * zoom)
            textView.textContainer?.size = CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        } else {
            let box = TextMetrics.labelBox(for: e)
            let layout = TextLayout(text: textView.string.isEmpty ? " " : textView.string,
                                    family: e.fontFamily, fontSize: e.fontSize, maxWidth: box.width)
            let top = box.midY - layout.size.height / 2
            let sceneRect = CGRect(x: e.x + box.minX, y: e.y + top, width: box.width, height: layout.size.height)
            frame = canvas.viewport.toView(sceneRect)
            textView.textContainer?.size = CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        }
        textView.frameCenterRotation = 0
        textView.frame = frame
        if e.type == .text, e.textAlign != .left {
            // Keep the alignment anchor stable while typing.
            let extra = fontSize
            textView.frame.origin.x -= e.textAlign == .center ? extra / 2 : extra
        }
        // Match the element rotation around the shape's center.
        if e.angle != 0 && !e.type.isLinear {
            let center = canvas.viewport.toView(e.center)
            let shift = frame.center.rotated(around: center, by: e.angle) - frame.center
            textView.frame.origin = textView.frame.origin + shift
            textView.frameCenterRotation = -e.angle * 180 / .pi
        }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        let text = textView.string
        canvas.store.update(elementId) { e in
            e.text = text
            TextFitter.fit(&e)
        }
        canvas.store.refreshBindings(for: [elementId])
        layout()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            canvas.endTextEditing()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            canvas.endTextEditing()
            return true
        }
        if selector == #selector(NSResponder.insertTab(_:)) {
            canvas.endTextEditing()
            return true
        }
        return false
    }

    func undoManager(for view: NSTextView) -> UndoManager? { localUndo }

    func tearDown() {
        textView.delegate = nil
        textView.removeFromSuperview()
    }
}

extension CanvasView {
    func beginTextEditing(elementId: String, isNew: Bool) {
        if textEditor != nil { endTextEditing() }
        guard let e = store.element(elementId), !e.locked else { return }
        store.beginInteraction()
        editor.isEditingText = true
        textEditor = TextEditingController(canvas: self, elementId: e.id, isNew: isNew)
        needsDisplay = true
    }

    func endTextEditing() {
        guard let te = textEditor else { return }
        textEditor = nil
        te.tearDown()
        editor.isEditingText = false
        if let e = store.element(te.elementId), e.type == .text,
           e.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.remove([e.id])
        }
        store.endInteraction(te.isNew ? "Add Text" : "Edit Text")
        window?.makeFirstResponder(self)
        if editor.tool == .text { editor.finishedCreating() }
        editor.hasInteracted = true
        needsDisplay = true
    }
}
