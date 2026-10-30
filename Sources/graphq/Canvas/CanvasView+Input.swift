import AppKit
import SketchCore
import SketchRender
import UniformTypeIdentifiers

extension CanvasView {
    // MARK: Pointer

    func pointerEvent(_ event: NSEvent) -> PointerEvent {
        let v = convert(event.locationInWindow, from: nil)
        let flags = event.modifierFlags
        let isTablet = event.subtype == .tabletPoint
        return PointerEvent(scene: viewport.toScene(v), view: v,
                            shift: flags.contains(.shift), option: flags.contains(.option),
                            command: flags.contains(.command), clickCount: event.clickCount,
                            pressure: isTablet ? Double(event.pressure) : nil)
    }

    override func mouseDown(with event: NSEvent) {
        if textEditor != nil {
            endTextEditing()
            if editor.tool == .text { return }
        }
        window?.makeFirstResponder(self)
        let p = pointerEvent(event)
        if spacePanning {
            panLast = p.view
            currentCursor.set()
            return
        }
        tool.mouseDown(p)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = pointerEvent(event)
        lastMouseView = p.view
        if let last = panLast {
            pan(byView: p.view - last)
            panLast = p.view
            return
        }
        tool.mouseDragged(p)
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if panLast != nil {
            panLast = nil
            currentCursor.set()
            return
        }
        tool.mouseUp(pointerEvent(event))
        currentCursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = pointerEvent(event)
        lastMouseView = p.view
        if spacePanning { return }
        tool.mouseMoved(p)
    }

    override func mouseExited(with event: NSEvent) {
        lastMouseView = nil
    }

    // Middle mouse button pans.
    override func otherMouseDown(with event: NSEvent) {
        panLast = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    override func otherMouseDragged(with event: NSEvent) {
        let v = convert(event.locationInWindow, from: nil)
        if let last = panLast { pan(byView: v - last) }
        panLast = v
    }

    override func otherMouseUp(with event: NSEvent) {
        panLast = nil
        currentCursor.set()
    }

    // MARK: Trackpad / wheel

    override func scrollWheel(with event: NSEvent) {
        let v = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            // ⌘ + wheel zooms around the pointer.
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            setZoom(viewport.zoom * (1 + delta), anchor: v)
            return
        }
        var dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { dx *= 10; dy *= 10 }
        if event.modifierFlags.contains(.shift) && dx == 0 { swap(&dx, &dy) }
        pan(byView: CGPoint(x: dx, y: dy))
    }

    override func magnify(with event: NSEvent) {
        let v = convert(event.locationInWindow, from: nil)
        setZoom(viewport.zoom * (1 + event.magnification), anchor: v)
    }

    override func smartMagnify(with event: NSEvent) {
        if abs(viewport.zoom - 1) > 0.01 { setZoom(1, anchor: convert(event.locationInWindow, from: nil)) } else { zoomToFit(selectionOnly: false) }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        if tool.keyDown(event) { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""
        let plain = flags.subtracting([.shift, .capsLock, .numericPad, .function]).isEmpty

        switch event.keyCode {
        case 53: // escape
            if store.isInteracting { tool.cancel() }
            if editor.showShortcuts { editor.showShortcuts = false; return }
            if store.editingGroupId != nil { store.editingGroupId = nil; return }
            if editor.tool != .selection { editor.tool = .selection; return }
            store.clearSelection()
            return
        case 51, 117: // delete, forward delete
            store.deleteSelection()
            return
        case 36, 76: // return, enter
            if store.selection.count == 1, let id = store.selection.first, let e = store.element(id),
               e.type == .text || e.type.isContainer, !e.locked {
                beginTextEditing(elementId: id, isNew: false)
            }
            return
        case 123, 124, 125, 126: // arrows
            let step: CGFloat = store.settings.gridEnabled ? Snapping.gridSize : (flags.contains(.shift) ? 10 : 1)
            let d: CGPoint = switch event.keyCode {
            case 123: CGPoint(x: -step, y: 0)
            case 124: CGPoint(x: step, y: 0)
            case 125: CGPoint(x: 0, y: step)
            default: CGPoint(x: 0, y: -step)
            }
            store.nudgeSelection(d)
            return
        case 49: // space
            if !event.isARepeat && !spacePanning {
                spacePanning = true
                currentCursor.set()
            }
            return
        default:
            break
        }

        if plain, let c = chars.first {
            if c == "?" || (c == "/" && flags.contains(.shift)) { editor.showShortcuts.toggle(); return }
            if flags.contains(.shift) {
                if chars == "!" || event.keyCode == 18 { zoomToFit(selectionOnly: false); return }
                if chars == "@" || event.keyCode == 19 { zoomToFit(selectionOnly: true); return }
            }
            if !flags.contains(.shift) {
                if c == "q" { editor.toolLocked.toggle(); return }
                if let digit = c.wholeNumberValue {
                    // Excalidraw-style number shortcuts.
                    let order: [ToolKind] = [.eraser, .selection, .rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image]
                    if digit < order.count { editor.selectTool(order[digit]); return }
                }
                if let t = ToolKind.forKey(c) { editor.selectTool(t); return }
            }
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spacePanning = false
            panLast = nil
            currentCursor.set()
            return
        }
        super.keyUp(with: event)
    }

    /// Fallback for ⌘= (the menu shows ⌘+).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "=" {
            zoomStep(in: true)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Responder actions (Edit menu)

    @objc func copy(_ sender: Any?) { copySelection() }

    @objc func cut(_ sender: Any?) {
        copySelection()
        store.perform("Cut") { store.remove(store.selection.filter { store.element($0)?.locked == false }) }
    }

    @objc func paste(_ sender: Any?) { pasteFromClipboard() }

    @objc func delete(_ sender: Any?) { store.deleteSelection() }

    override func selectAll(_ sender: Any?) {
        editor.tool = .selection
        store.selectAll()
    }

    @objc func duplicate(_ sender: Any?) { store.duplicateSelection() }

    func copySelection() {
        let selected = store.selectedElements
        guard !selected.isEmpty else { return }
        SceneClipboard.write(selected, files: store.files)
    }

    func copyAsPNG() {
        let list = store.selection.isEmpty ? store.elements : store.selectedElements
        guard !list.isEmpty else { NSSound.beep(); return }
        do {
            try SceneClipboard.writePNG(list, files: store.files, darkMode: isDark)
        } catch {
            presentError(error)
        }
    }

    func pasteFromClipboard() {
        guard let content = SceneClipboard.read() else { NSSound.beep(); return }
        insert(content, at: pasteTarget, name: "Paste")
    }

    func insert(_ content: SceneClipboard.Content, at target: CGPoint, name: String) {
        switch content {
        case .scene(let scene):
            let bounds = SceneGeometry.bounds(of: scene.elements)
            guard !bounds.isNull else { return }
            var offset = target - bounds.center
            if store.settings.gridEnabled { offset = Snapping.snapToGrid(offset) }
            let copies = Groups.duplicate(scene.elements, offset: offset)
            let files = scene.files.values.filter { f in copies.contains { $0.fileId == f.id } }
            editor.tool = .selection
            store.insertNew(copies, files: Array(files), name: name)
        case .image(let data, let mime):
            insertImage(data, mimeType: mime, at: target)
        case .text(let string):
            var e = editor.style.makeElement(.text)
            e.text = string
            TextFitter.fit(&e)
            e.x = target.x - e.width / 2
            e.y = target.y - e.height / 2
            editor.tool = .selection
            store.insertNew([e], name: name)
        }
        editor.hasInteracted = true
    }

    func insertImage(_ data: Data, mimeType: String, at target: CGPoint) {
        let file = BinaryFile(id: BinaryFile.makeId(for: data), mimeType: mimeType, data: data)
        var size = ImageImport.pixelSize(data) ?? CGSize(width: 300, height: 200)
        // Retina screenshots are 2x; show images at a comfortable default size.
        let maxSide: CGFloat = 480
        let scale = min(1, maxSide / max(size.width, size.height))
        size = CGSize(width: size.width * scale, height: size.height * scale)
        var e = editor.style.makeElement(.image)
        e.fileId = file.id
        e.width = size.width
        e.height = size.height
        e.x = target.x - size.width / 2
        e.y = target.y - size.height / 2
        e.fillColor = .transparent
        editor.tool = .selection
        store.insertNew([e], files: [file], name: "Insert Image")
    }

    func insertImageFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageImport.supportedTypes
        panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            MainActor.assumeIsolated {
                guard let img = ImageImport.load(url) else { NSSound.beep(); return }
                self.insertImage(img.data, mimeType: img.mimeType, at: self.sceneCenter)
            }
        }
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = pointerEvent(event)
        if let hit = store.hitTest(p.scene, tolerance: sceneDistance(6)), !store.selection.contains(hit.id) {
            store.select([hit.id])
        }
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            menu.addItem(i)
        }
        if store.selection.isEmpty {
            item("Paste", #selector(paste(_:)), "v")
            item("Select All", #selector(selectAll(_:)), "a")
            menu.addItem(.separator())
            item(store.settings.gridEnabled ? "Hide Grid" : "Show Grid", #selector(menuToggleGrid(_:)), "'")
            item("Zoom to Fit", #selector(menuZoomToFit(_:)), "1", .shift)
            return menu
        }
        item("Cut", #selector(cut(_:)), "x")
        item("Copy", #selector(copy(_:)), "c")
        item("Paste", #selector(paste(_:)), "v")
        item("Copy as PNG", #selector(menuCopyAsPNG(_:)), "c", [.shift, .option])
        menu.addItem(.separator())
        item("Duplicate", #selector(duplicate(_:)), "d")
        item("Delete", #selector(delete(_:)), "\u{8}", [])
        menu.addItem(.separator())
        item("Bring to Front", #selector(menuFront(_:)), "]", [.command, .option])
        item("Send to Back", #selector(menuBack(_:)), "[", [.command, .option])
        if store.selection.count > 1 { item("Group", #selector(menuGroup(_:)), "g") }
        if store.canUngroup { item("Ungroup", #selector(menuUngroup(_:)), "g", [.command, .shift]) }
        item(store.selectionIsLocked ? "Unlock" : "Lock", #selector(menuLock(_:)), "l", [.command, .shift])
        return menu
    }

    @objc private func menuToggleGrid(_ sender: Any?) { store.setGridEnabled(!store.settings.gridEnabled) }
    @objc private func menuZoomToFit(_ sender: Any?) { zoomToFit(selectionOnly: false) }
    @objc private func menuCopyAsPNG(_ sender: Any?) { copyAsPNG() }
    @objc private func menuFront(_ sender: Any?) { store.arrange(.front) }
    @objc private func menuBack(_ sender: Any?) { store.arrange(.back) }
    @objc private func menuGroup(_ sender: Any?) { store.groupSelection() }
    @objc private func menuUngroup(_ sender: Any?) { store.ungroupSelection() }
    @objc private func menuLock(_ sender: Any?) { store.toggleLock() }
}

// MARK: - Menu validation

extension CanvasView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)), #selector(duplicate(_:)):
            return !store.selection.isEmpty
        case #selector(paste(_:)):
            return SceneClipboard.canRead
        default:
            return true
        }
    }
}

// MARK: - Drag & drop

extension CanvasView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let target = viewport.toScene(convert(sender.draggingLocation, from: nil))
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            var offset: CGFloat = 0
            for url in urls {
                let point = target + CGPoint(x: offset, y: offset)
                if let content = DroppedFile.content(of: url) {
                    insert(content, at: point, name: "Drop")
                    offset += 24
                }
            }
            return true
        }
        if let data = pb.data(forType: .png) {
            insertImage(data, mimeType: "image/png", at: target)
            return true
        }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            insertImage(png, mimeType: "image/png", at: target)
            return true
        }
        return false
    }
}

enum DroppedFile {
    /// Images become image elements; .graphq/.excalidraw files are merged into the scene.
    static func content(of url: URL) -> SceneClipboard.Content? {
        let ext = url.pathExtension.lowercased()
        if ext == "graphq" || ext == "sketchboard", let data = try? Data(contentsOf: url), let scene = try? DocumentCodec.decode(data) {
            return .scene(scene)
        }
        if ext == "excalidraw", let data = try? Data(contentsOf: url), let scene = try? ExcalidrawImporter.importScene(data) {
            return .scene(scene)
        }
        if let img = ImageImport.load(url) { return .image(img.data, mimeType: img.mimeType) }
        return nil
    }
}

extension SceneClipboard {
    static var canRead: Bool {
        let pb = NSPasteboard.general
        return pb.availableType(from: [elementsType, .png, .tiff, .string, .fileURL]) != nil
    }
}
