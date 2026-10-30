import AppKit
import SketchCore
import SwiftUI
import UniformTypeIdentifiers

/// Native menu bar. Commands act on the focused window's editor.
struct SketchCommands: Commands {
    @FocusedValue(\.editor) private var editor

    private var store: SceneStore? { editor?.store }
    private var hasSelection: Bool { !(store?.selection.isEmpty ?? true) }
    /// Single-key shortcuts must not fire while typing into a text element.
    private var canUseKeys: Bool { editor != nil && editor?.isEditingText == false }

    var body: some Commands {
        // File
        CommandGroup(after: .importExport) {
            Button("Import Excalidraw…") { importExcalidraw() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button("Export…") { editor?.showExport = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(store?.isEmpty ?? true)
        }

        // Edit
        CommandGroup(after: .pasteboard) {
            Button("Copy as PNG") { editor?.copyAsPNG() }
                .keyboardShortcut("c", modifiers: [.command, .shift, .option])
                .disabled(store?.isEmpty ?? true)
            Button("Duplicate") { store?.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!hasSelection || !canUseKeys)
            Divider()
            Button("Deselect") { store?.clearSelection() }
                .disabled(!hasSelection)
        }

        // View
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { editor?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(editor == nil)
            Button("Zoom Out") { editor?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(editor == nil)
            Button("Actual Size") { editor?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(editor == nil)
            Button("Zoom to Fit") { editor?.zoomToFit() }
                .keyboardShortcut("1", modifiers: .shift)
                .disabled(!canUseKeys)
            Button("Zoom to Selection") { editor?.zoomToSelection() }
                .keyboardShortcut("2", modifiers: .shift)
                .disabled(!canUseKeys || !hasSelection)
            Divider()
            Toggle("Show Grid", isOn: Binding(
                get: { store?.settings.gridEnabled ?? false },
                set: { store?.setGridEnabled($0) }))
                .keyboardShortcut("'", modifiers: .command)
                .disabled(editor == nil)
            Toggle("Snap to Objects", isOn: Binding(
                get: { editor?.snapToObjects ?? false },
                set: { editor?.snapToObjects = $0 }))
                .keyboardShortcut("s", modifiers: .option)
                .disabled(editor == nil)
            Divider()
            Button("Keyboard Shortcuts") { editor?.showShortcuts.toggle() }
                .keyboardShortcut("/", modifiers: [.command])
                .disabled(editor == nil)
            Divider()
        }

        // Tools
        CommandMenu("Tools") {
            ForEach(ToolKind.allCases) { tool in
                let button = Button {
                    editor?.selectTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.symbol)
                }
                .disabled(!canUseKeys)
                if let key = tool.shortcut {
                    button.keyboardShortcut(KeyEquivalent(key), modifiers: [])
                } else {
                    button.keyboardShortcut("k", modifiers: [.command, .shift])
                }
            }
            Divider()
            Toggle("Keep Tool Active", isOn: Binding(
                get: { editor?.toolLocked ?? false },
                set: { editor?.toolLocked = $0 }))
                .keyboardShortcut("q", modifiers: [])
                .disabled(!canUseKeys)
        }

        // Arrange
        CommandMenu("Arrange") {
            Button("Bring Forward") { store?.arrange(.forward) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!hasSelection)
            Button("Send Backward") { store?.arrange(.backward) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!hasSelection)
            Button("Bring to Front") { store?.arrange(.front) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!hasSelection)
            Button("Send to Back") { store?.arrange(.back) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!hasSelection)
            Divider()
            Button("Group") { store?.groupSelection() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled((store?.selection.count ?? 0) < 2)
            Button("Ungroup") { store?.ungroupSelection() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!(store?.canUngroup ?? false))
            Divider()
            Menu("Align") {
                Button("Left Edges") { store?.align(.left) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                Button("Horizontal Centers") { store?.align(.centerX) }
                Button("Right Edges") { store?.align(.right) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                Divider()
                Button("Top Edges") { store?.align(.top) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Button("Vertical Centers") { store?.align(.centerY) }
                Button("Bottom Edges") { store?.align(.bottom) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
            }
            .disabled((store?.selection.count ?? 0) < 2)
            Menu("Distribute") {
                Button("Horizontally") { store?.distribute(.horizontal) }
                    .keyboardShortcut("h", modifiers: [.option, .shift])
                Button("Vertically") { store?.distribute(.vertical) }
                    .keyboardShortcut("v", modifiers: [.option, .shift])
            }
            .disabled((store?.selection.count ?? 0) < 3)
            Divider()
            Button(store?.selectionIsLocked == true ? "Unlock" : "Lock") { store?.toggleLock() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!hasSelection)
            Button("Unlock All") { store?.unlockAll() }
        }

        CommandGroup(replacing: .help) {
            Button("graphq Keyboard Shortcuts") { editor?.showShortcuts = true }
                .disabled(editor == nil)
        }
    }

    @MainActor
    private func importExcalidraw() {
        guard let editor else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.excalidraw, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let scene = try ExcalidrawImporter.importScene(data)
            editor.canvas?.insert(.scene(scene), at: editor.canvas?.sceneCenter ?? .zero, name: "Import")
            editor.zoomToSelection()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
