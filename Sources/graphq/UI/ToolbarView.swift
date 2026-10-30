import SwiftUI

/// Floating tool palette, centered at the top of the canvas.
struct ToolbarView: View {
    @Bindable var editor: Editor

    private let groups: [[ToolKind]] = [
        [.hand, .selection],
        [.rectangle, .diamond, .ellipse, .arrow, .line, .freedraw, .text, .image],
        [.eraser],
    ]

    var body: some View {
        HStack(spacing: 2) {
            ToolButton(symbol: editor.toolLocked ? "lock.fill" : "lock.open",
                       isSelected: editor.toolLocked, shortcut: "Q",
                       help: "Keep selected tool active after drawing — Q") {
                editor.toolLocked.toggle()
            }
            divider
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { divider }
                ForEach(group) { tool in
                    ToolButton(symbol: tool.symbol, isSelected: editor.tool == tool,
                               shortcut: tool.shortcut.map { String($0).uppercased() },
                               help: tool.shortcut.map { "\(tool.title) — \(String($0).uppercased())" } ?? tool.title) {
                        editor.selectTool(tool)
                    }
                }
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 1, y: 0.5)
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}

private struct ToolButton: View {
    let symbol: String
    let isSelected: Bool
    let shortcut: String?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 34, height: 32)
                .overlay(alignment: .bottomTrailing) {
                    if let shortcut {
                        Text(shortcut)
                            .font(.system(size: 7.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .padding(.trailing, 3)
                            .padding(.bottom, 1)
                    }
                }
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : hovering ? Color.primary.opacity(0.06) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

/// Bottom-right zoom control: − 100% +
struct ZoomControls: View {
    @Bindable var editor: Editor

    var body: some View {
        HStack(spacing: 0) {
            button("minus", help: "Zoom out  ⌘−") { editor.zoomOut() }
            Button {
                editor.resetZoom()
            } label: {
                Text("\(Int((editor.zoom * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .frame(minWidth: 46)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset zoom  ⌘0")
            button("plus", help: "Zoom in  ⌘+") { editor.zoomIn() }
        }
        .padding(.horizontal, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

/// Bottom-left undo/redo capsule.
struct HistoryControls: View {
    @Environment(\.undoManager) private var undoManager
    let revision: Int

    var body: some View {
        HStack(spacing: 0) {
            Button { undoManager?.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 28).contentShape(Rectangle())
            }
            .disabled(!(undoManager?.canUndo ?? false))
            .help("Undo  ⌘Z")
            Button { undoManager?.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 30, height: 28).contentShape(Rectangle())
            }
            .disabled(!(undoManager?.canRedo ?? false))
            .help("Redo  ⇧⌘Z")
        }
        .id(revision)
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }
}
