import SwiftUI

/// Subtle hint on an empty canvas; disappears after the first action.
struct EmptyStateHint: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Pick a tool and start sketching")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                hint("R", "Rectangle")
                hint("O", "Ellipse")
                hint("A", "Arrow")
                hint("P", "Draw")
                hint("T", "Text")
                hint("?", "Shortcuts")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .allowsHitTesting(false)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(key)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
    }
}

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.primary.opacity(0.1)))
    }
}

/// Keyboard shortcut cheat sheet (toggled with `?`).
struct ShortcutsOverlay: View {
    let close: () -> Void

    private let sections: [(String, [(String, String)])] = [
        ("Tools", [
            ("V", "Select"), ("H", "Hand"), ("R", "Rectangle"), ("D", "Diamond"), ("O", "Ellipse"),
            ("A", "Arrow"), ("L", "Line"), ("P", "Draw"), ("T", "Text"), ("E", "Eraser"),
            ("⇧⌘K", "Insert image"), ("Q", "Keep tool active"),
        ]),
        ("View", [
            ("Space + drag", "Pan"), ("⌘ + scroll", "Zoom"), ("Pinch", "Zoom (trackpad)"),
            ("⌘+ / ⌘−", "Zoom in / out"), ("⌘0", "Reset zoom"), ("⇧1", "Zoom to fit"),
            ("⇧2", "Zoom to selection"), ("⌘'", "Toggle grid"), ("⌥S", "Snap to objects"),
        ]),
        ("Edit", [
            ("⌘Z / ⇧⌘Z", "Undo / redo"), ("⌘C / ⌘V", "Copy / paste"), ("⇧⌥⌘C", "Copy as PNG"),
            ("⌘D", "Duplicate"), ("⌥ + drag", "Drag a copy"), ("⌫", "Delete"), ("⌘A", "Select all"),
            ("⌘G / ⇧⌘G", "Group / ungroup"), ("⌘[ / ⌘]", "Backward / forward"),
            ("⌥⌘[ / ⌥⌘]", "To back / front"), ("⇧⌘L", "Lock"), ("↵", "Edit text"),
            ("Shift", "Keep proportions / 15°"), ("⌥", "Resize from center"), ("⌘ (drag)", "Disable snapping"),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Keyboard shortcuts").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                HStack(alignment: .top, spacing: 28) {
                    ForEach(sections, id: \.0) { title, items in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                let (key, label) = item
                                HStack {
                                    Text(label).font(.system(size: 12.5))
                                    Spacer(minLength: 16)
                                    KeyCap(key)
                                }
                            }
                        }
                        .frame(width: 210)
                    }
                }
            }
            .padding(24)
            .fixedSize()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
        }
    }
}
