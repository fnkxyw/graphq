import AppKit
import SwiftUI

/// Window content: full-bleed canvas with floating chrome on top.
struct ContentView: View {
    @State private var editor: Editor
    @Environment(\.undoManager) private var undoManager
    @AppStorage(Preferences.showHintsKey) private var showHints = true

    init(document: SketchDocument) {
        _editor = State(initialValue: Editor(store: document.store))
    }

    private var store: SceneStore { editor.store }

    var body: some View {
        ZStack {
            CanvasRepresentable(editor: editor)
                .ignoresSafeArea()

            VStack {
                ToolbarView(editor: editor)
                    .padding(.top, 10)
                Spacer()
            }

            HStack(alignment: .top) {
                if !store.selection.isEmpty && !editor.isEditingText {
                    PropertiesPanel(editor: editor)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 64)
            .padding(.bottom, 60)

            VStack {
                Spacer()
                HStack {
                    HistoryControls(revision: store.revision)
                    Spacer()
                    ZoomControls(editor: editor)
                }
                .padding(12)
            }

            if showHints && store.isEmpty && !editor.hasInteracted && editor.tool == .selection {
                EmptyStateHint()
                    .transition(.opacity)
            }

            if editor.showShortcuts {
                ShortcutsOverlay { editor.showShortcuts = false }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.selection.isEmpty)
        .animation(.easeOut(duration: 0.2), value: editor.showShortcuts)
        .animation(.easeOut(duration: 0.25), value: editor.hasInteracted)
        .focusedSceneValue(\.editor, editor)
        .sheet(isPresented: $editor.showExport) {
            ExportSheet(editor: editor)
        }
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { store.undoManager = undoManager }
    }
}

/// Hosts the AppKit canvas.
struct CanvasRepresentable: NSViewRepresentable {
    let editor: Editor

    func makeNSView(context: Context) -> CanvasView {
        CanvasView(editor: editor)
    }

    func updateNSView(_ view: CanvasView, context: Context) {}
}
