import SketchCore
import SwiftUI

/// Floating style inspector shown while something is selected.
/// Every change also becomes the default for the next element (Excalidraw behavior).
struct PropertiesPanel: View {
    @Bindable var editor: Editor
    @State private var contentHeight: CGFloat = 0

    private var store: SceneStore { editor.store }

    var body: some View {
        let selected = store.selectedElements
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                content(selected)
                    .padding(12)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: HeightKey.self, value: g.size.height)
                    })
            }
            .frame(height: min(contentHeight, proxy.size.height))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
        }
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
        .frame(width: 214)
    }

    @ViewBuilder
    private func content(_ selected: [Element]) -> some View {
        let types = Set(selected.map(\.type))
        let first = selected.first
        let shapes: Set<ElementType> = [.rectangle, .ellipse, .diamond, .arrow, .line]
        let locked = selected.allSatisfy(\.locked)

        VStack(alignment: .leading, spacing: 14) {
            if !types.subtracting([.image]).isEmpty {
                PanelSection(title: types == [.text] ? "Text color" : "Stroke") {
                    ColorRow(colors: Palette.strokes, current: first?.strokeColor,
                             onPick: { c in set("Stroke Color", { $0.strokeColor = c }) { $0.strokeColor = c } },
                             onLivePick: { c in setLive("Stroke Color", { $0.strokeColor = c }) { $0.strokeColor = c } })
                }
            }
            if selected.contains(where: { $0.type.supportsFill }) {
                PanelSection(title: "Background") {
                    ColorRow(colors: Palette.fills, current: selected.first(where: { $0.type.supportsFill })?.fillColor,
                             onPick: { c in setFill(c) },
                             onLivePick: { c in
                                 setLive("Background", { if $0.type.supportsFill { $0.fillColor = c } }) { $0.fillColor = c }
                             })
                }
                if selected.contains(where: { $0.type.supportsFill && !$0.fillColor.isTransparent }) {
                    PanelSection(title: "Fill") {
                        HStack(spacing: 4) {
                            ForEach([SketchCore.FillStyle.hachure, .crossHatch, .solid], id: \.self) { fs in
                                ChipButton(isSelected: first?.fillStyle == fs, help: fs.title) {
                                    set("Fill Style", { $0.fillStyle = fs }) { $0.fillStyle = fs }
                                } label: { FillStyleIcon(style: fs) }
                            }
                        }
                    }
                }
            }
            if !types.isDisjoint(with: shapes.union([.freedraw])) {
                PanelSection(title: "Stroke width") {
                    HStack(spacing: 4) {
                        ForEach([(1.0, "Thin"), (2.0, "Bold"), (4.0, "Extra bold")], id: \.0) { w, name in
                            ChipButton(isSelected: first?.strokeWidth == w, help: name) {
                                set("Stroke Width", { $0.strokeWidth = w }) { $0.strokeWidth = w }
                            } label: { StrokeWidthIcon(width: w) }
                        }
                    }
                }
            }
            if !types.isDisjoint(with: shapes) {
                PanelSection(title: "Stroke style") {
                    HStack(spacing: 4) {
                        ForEach(SketchCore.StrokeStyle.allCases, id: \.self) { st in
                            ChipButton(isSelected: first?.strokeStyle == st, help: st.rawValue.capitalized) {
                                set("Stroke Style", { if $0.type != .freedraw { $0.strokeStyle = st } }) { $0.strokeStyle = st }
                            } label: { StrokeStyleIcon(style: st) }
                        }
                    }
                }
                PanelSection(title: "Sloppiness") {
                    HStack(spacing: 4) {
                        ForEach(Sloppiness.allCases, id: \.self) { s in
                            ChipButton(isSelected: first.map { Sloppiness(roughness: $0.roughness) } == s, help: s.title) {
                                set("Sloppiness", { $0.roughness = s.rawValue }) { $0.roughness = s.rawValue }
                            } label: { SloppinessIcon(level: s) }
                        }
                    }
                }
            }
            if !types.isDisjoint(with: [.rectangle, .diamond, .image]) {
                PanelSection(title: "Edges") {
                    HStack(spacing: 4) {
                        ForEach([(0.0, "Sharp"), (8.0, "Soft"), (20.0, "Round")], id: \.0) { r, name in
                            ChipButton(isSelected: first?.roundness == r, help: name) {
                                set("Edges", { if $0.type == .rectangle || $0.type == .diamond || $0.type == .image { $0.roundness = r } }) { $0.roundness = r }
                            } label: { EdgeIcon(radius: r / 2.2) }
                        }
                    }
                }
            }
            if !types.isDisjoint(with: [.arrow, .line]) {
                arrowSection(selected)
            }
            if types.contains(.text) || !types.isDisjoint(with: [.rectangle, .ellipse, .diamond]) {
                textSection(first)
            }
            PanelSection(title: "Opacity") {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { (first?.opacity ?? 1) * 100 },
                        set: { v in setLive("Opacity", { $0.opacity = v / 100 }) { $0.opacity = v / 100 } }
                    ), in: 0...100)
                    .controlSize(.small)
                    Text("\(Int(((first?.opacity ?? 1) * 100).rounded()))")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
            PanelSection(title: "Layers") {
                HStack(spacing: 4) {
                    ChipButton(help: "Send to back  ⌥⌘[") { store.arrange(.back) } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }
                    ChipButton(help: "Send backward  ⌘[") { store.arrange(.backward) } label: { Image(systemName: "arrow.down.square") }
                    ChipButton(help: "Bring forward  ⌘]") { store.arrange(.forward) } label: { Image(systemName: "arrow.up.square") }
                    ChipButton(help: "Bring to front  ⌥⌘]") { store.arrange(.front) } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                }
            }
            if selected.count > 1 {
                PanelSection(title: "Align") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            ChipButton(help: "Align left") { store.align(.left) } label: { Image(systemName: "align.horizontal.left") }
                            ChipButton(help: "Center horizontally") { store.align(.centerX) } label: { Image(systemName: "align.horizontal.center") }
                            ChipButton(help: "Align right") { store.align(.right) } label: { Image(systemName: "align.horizontal.right") }
                            ChipButton(help: "Distribute horizontally") { store.distribute(.horizontal) } label: { Image(systemName: "distribute.horizontal.center") }
                        }
                        HStack(spacing: 4) {
                            ChipButton(help: "Align top") { store.align(.top) } label: { Image(systemName: "align.vertical.top") }
                            ChipButton(help: "Center vertically") { store.align(.centerY) } label: { Image(systemName: "align.vertical.center") }
                            ChipButton(help: "Align bottom") { store.align(.bottom) } label: { Image(systemName: "align.vertical.bottom") }
                            ChipButton(help: "Distribute vertically") { store.distribute(.vertical) } label: { Image(systemName: "distribute.vertical.center") }
                        }
                    }
                }
            }
            PanelSection(title: "Actions") {
                HStack(spacing: 4) {
                    ChipButton(help: "Duplicate  ⌘D") { store.duplicateSelection() } label: { Image(systemName: "plus.square.on.square") }
                    ChipButton(help: "Delete  ⌫") { store.deleteSelection() } label: { Image(systemName: "trash") }
                    ChipButton(isSelected: locked, help: locked ? "Unlock  ⇧⌘L" : "Lock  ⇧⌘L") { store.toggleLock() } label: {
                        Image(systemName: locked ? "lock.fill" : "lock.open")
                    }
                    if selected.count > 1 {
                        ChipButton(help: "Group  ⌘G") { store.groupSelection() } label: { Image(systemName: "rectangle.3.group") }
                    }
                    if store.canUngroup {
                        ChipButton(help: "Ungroup  ⇧⌘G") { store.ungroupSelection() } label: { Image(systemName: "rectangle.3.group.fill") }
                    }
                }
            }
        }
        .disabled(false)
    }

    @ViewBuilder
    private func arrowSection(_ selected: [Element]) -> some View {
        let linear = selected.first { $0.type.isLinear }
        PanelSection(title: "Arrow") {
            HStack(spacing: 4) {
                ChipButton(isSelected: linear?.curved == false, help: "Sharp") {
                    set("Arrow Type", { if $0.type.isLinear { $0.curved = false } }) { $0.curvedArrows = false }
                } label: { ArrowTypeIcon(curved: false) }
                ChipButton(isSelected: linear?.curved == true, help: "Curved") {
                    set("Arrow Type", { if $0.type.isLinear { $0.curved = true } }) { $0.curvedArrows = true }
                } label: { ArrowTypeIcon(curved: true) }
                Spacer(minLength: 6)
                arrowheadMenu(current: linear?.startArrowhead ?? .none, isStart: true)
                arrowheadMenu(current: linear?.endArrowhead ?? .arrow, isStart: false)
            }
        }
    }

    private func arrowheadMenu(current: Arrowhead, isStart: Bool) -> some View {
        Menu {
            ForEach(Arrowhead.allCases, id: \.self) { head in
                Button {
                    set("Arrowhead", { e in
                        guard e.type.isLinear else { return }
                        if e.type == .line { e.type = .arrow }
                        if isStart { e.startArrowhead = head } else { e.endArrowhead = head }
                    }) { s in if isStart { s.startArrowhead = head } else { s.endArrowhead = head } }
                } label: {
                    Label(head.title, systemImage: head.symbol)
                }
            }
        } label: {
            Image(systemName: current.symbol)
                .scaleEffect(x: isStart ? -1 : 1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .help(isStart ? "Start arrowhead" : "End arrowhead")
    }

    @ViewBuilder
    private func textSection(_ first: Element?) -> some View {
        PanelSection(title: "Font") {
            HStack(spacing: 4) {
                ForEach(FontFamily.allCases, id: \.self) { f in
                    ChipButton(isSelected: first?.fontFamily == f, help: f.title) {
                        set("Font", { $0.fontFamily = f }) { $0.fontFamily = f }
                    } label: { Image(systemName: f.symbol) }
                }
            }
        }
        PanelSection(title: "Font size") {
            HStack(spacing: 4) {
                ForEach([(16.0, "S"), (20.0, "M"), (28.0, "L"), (36.0, "XL")], id: \.0) { size, name in
                    ChipButton(isSelected: first?.fontSize == size, help: "\(Int(size)) pt") {
                        set("Font Size", { $0.fontSize = size }) { $0.fontSize = size }
                    } label: { Text(name).font(.system(size: 11, weight: .semibold)) }
                }
            }
        }
        PanelSection(title: "Text align") {
            HStack(spacing: 4) {
                ForEach(TextAlign.allCases, id: \.self) { a in
                    ChipButton(isSelected: first?.textAlign == a, help: a.rawValue.capitalized) {
                        set("Text Align", { $0.textAlign = a }) { $0.textAlign = a }
                    } label: { Image(systemName: "text.align\(a.rawValue)") }
                }
            }
        }
    }

    // MARK: Apply helpers

    private func set(_ name: String, _ body: @escaping (inout Element) -> Void, defaults: (inout StyleDefaults) -> Void) {
        defaults(&editor.style)
        store.applyStyle(name, body)
    }

    private func setLive(_ name: String, _ body: @escaping (inout Element) -> Void, defaults: (inout StyleDefaults) -> Void) {
        defaults(&editor.style)
        store.applyStyleLive(name, body)
    }

    private func setFill(_ c: RGBAColor) {
        editor.style.fillColor = c
        store.applyStyle("Background") { e in
            guard e.type.supportsFill else { return }
            e.fillColor = c
        }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Display names & symbols

extension SketchCore.FillStyle {
    var title: String {
        switch self {
        case .hachure: "Hachure"
        case .crossHatch: "Cross-hatch"
        case .solid: "Solid"
        }
    }
}

extension Sloppiness {
    var title: String {
        switch self {
        case .architect: "Architect"
        case .artist: "Artist"
        case .cartoonist: "Cartoonist"
        }
    }
}

extension FontFamily {
    var title: String {
        switch self {
        case .hand: "Hand-drawn"
        case .normal: "Normal"
        case .mono: "Code"
        }
    }

    var symbol: String {
        switch self {
        case .hand: "pencil.and.scribble"
        case .normal: "textformat"
        case .mono: "chevron.left.forwardslash.chevron.right"
        }
    }
}

extension Arrowhead {
    var title: String {
        switch self {
        case .none: "None"
        case .arrow: "Arrow"
        case .triangle: "Triangle"
        case .dot: "Dot"
        case .bar: "Bar"
        case .diamond: "Diamond"
        }
    }

    var symbol: String {
        switch self {
        case .none: "minus"
        case .arrow: "arrow.right"
        case .triangle: "arrowtriangle.right.fill"
        case .dot: "circle.fill"
        case .bar: "line.diagonal"
        case .diamond: "diamond.fill"
        }
    }
}
