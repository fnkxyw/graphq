import AppKit
import SketchCore
import SwiftUI

/// Muted, hand-picked palette (works in both themes thanks to smart inversion).
enum Palette {
    static let strokes: [RGBAColor] = [
        "#1f2328", "#737b86", "#d64545", "#e07b39", "#c99a1e",
        "#2f9e60", "#1c9c96", "#3f73e0", "#8058d6", "#d0508e",
    ].compactMap(RGBAColor.init(hex:))

    static let fills: [RGBAColor] = [.transparent] + [
        "#e9ecef", "#ffd8d8", "#ffe2c7", "#fff1b8",
        "#d3f2dc", "#c9f0ec", "#d7e5ff", "#e6dcff", "#fbd9ea",
    ].compactMap(RGBAColor.init(hex:))
}

extension RGBAColor {
    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }
}

// MARK: - Panel building blocks

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            content
        }
    }
}

/// Small square button used across the panel; highlights when selected.
struct ChipButton<Label: View>: View {
    var isSelected = false
    var help: String
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18)
                              : hovering ? Color.primary.opacity(0.07) : .clear)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct ColorSwatch: View {
    let color: RGBAColor
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                if color.isTransparent {
                    // Transparent: a checkerboard-free "no fill" slash.
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    Path { p in
                        p.move(to: CGPoint(x: 5, y: 17)); p.addLine(to: CGPoint(x: 17, y: 5))
                    }
                    .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill((scheme == .dark ? color.adaptedForDarkMode() : color).swiftUI)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
            }
            .frame(width: 22, height: 22)
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .help(color.hexString)
    }
}

/// Row of swatches + system color picker.
struct ColorRow: View {
    let colors: [RGBAColor]
    let current: RGBAColor?
    let onPick: (RGBAColor) -> Void
    let onLivePick: (RGBAColor) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(26), spacing: 2), count: 6)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
            ForEach(colors, id: \.self) { c in
                ColorSwatch(color: c, isSelected: current == c) { onPick(c) }
            }
            ColorWellButton(current: current ?? .ink, onChange: onLivePick)
                .help("Custom color")
        }
    }
}

/// Compact custom-color button that drives the shared system color panel.
struct ColorWellButton: View {
    let current: RGBAColor
    let onChange: (RGBAColor) -> Void

    var body: some View {
        Button {
            ColorPanelBridge.shared.open(with: current, onChange: onChange)
        } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Routes NSColorPanel changes to the most recently opened color well.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((RGBAColor) -> Void)?

    func open(with color: RGBAColor, onChange: @escaping (RGBAColor) -> Void) {
        self.onChange = nil
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        self.onChange = onChange
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let c = sender.color.usingColorSpace(.sRGB) else { return }
        onChange?(RGBAColor(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent)))
    }
}

// MARK: - Little drawn icons (SF Symbols has no glyphs for these)

struct StrokeWidthIcon: View {
    let width: CGFloat
    var body: some View {
        Capsule().frame(width: 16, height: width)
    }
}

struct StrokeStyleIcon: View {
    let style: SketchCore.StrokeStyle
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 8)); p.addLine(to: CGPoint(x: 18, y: 8))
        }
        .stroke(style: SwiftUI.StrokeStyle(lineWidth: 2, lineCap: .round,
                                           dash: style == .dashed ? [4, 3] : style == .dotted ? [0.5, 3.5] : []))
        .frame(width: 20, height: 16)
    }
}

struct SloppinessIcon: View {
    let level: Sloppiness
    var body: some View {
        Path { p in
            switch level {
            case .architect:
                p.move(to: CGPoint(x: 2, y: 12)); p.addCurve(to: CGPoint(x: 18, y: 4), control1: CGPoint(x: 8, y: 12), control2: CGPoint(x: 12, y: 4))
            case .artist:
                p.move(to: CGPoint(x: 2, y: 12)); p.addCurve(to: CGPoint(x: 18, y: 4), control1: CGPoint(x: 8, y: 13), control2: CGPoint(x: 12, y: 3))
                p.move(to: CGPoint(x: 3, y: 11)); p.addCurve(to: CGPoint(x: 17, y: 5), control1: CGPoint(x: 9, y: 11), control2: CGPoint(x: 11, y: 5))
            case .cartoonist:
                p.move(to: CGPoint(x: 2, y: 12)); p.addCurve(to: CGPoint(x: 18, y: 4), control1: CGPoint(x: 6, y: 16), control2: CGPoint(x: 14, y: 0))
                p.move(to: CGPoint(x: 3, y: 10)); p.addCurve(to: CGPoint(x: 17, y: 6), control1: CGPoint(x: 9, y: 9), control2: CGPoint(x: 10, y: 7))
            }
        }
        .stroke(style: SwiftUI.StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .frame(width: 20, height: 16)
    }
}

struct FillStyleIcon: View {
    let style: SketchCore.FillStyle
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 1.4)
            switch style {
            case .solid:
                RoundedRectangle(cornerRadius: 3).fill()
            case .hachure, .crossHatch:
                Path { p in
                    for i in stride(from: -16.0, through: 16, by: 4) {
                        p.move(to: CGPoint(x: i, y: 16)); p.addLine(to: CGPoint(x: i + 16, y: 0))
                        if style == .crossHatch {
                            p.move(to: CGPoint(x: i, y: 0)); p.addLine(to: CGPoint(x: i + 16, y: 16))
                        }
                    }
                }
                .stroke(lineWidth: 1)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .frame(width: 16, height: 16)
    }
}

struct EdgeIcon: View {
    let radius: CGFloat
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: radius, style: .continuous)
            .trim(from: 0.0, to: 1)
            .stroke(lineWidth: 1.6)
            .frame(width: 15, height: 15)
            .mask(Rectangle().frame(width: 10, height: 10).offset(x: -3, y: -3))
            .frame(width: 16, height: 16)
    }
}

struct ArrowTypeIcon: View {
    let curved: Bool
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 14))
            if curved {
                p.addCurve(to: CGPoint(x: 18, y: 3), control1: CGPoint(x: 4, y: 2), control2: CGPoint(x: 12, y: 14))
            } else {
                p.addLine(to: CGPoint(x: 9, y: 4))
                p.addLine(to: CGPoint(x: 18, y: 12))
            }
        }
        .stroke(style: SwiftUI.StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .frame(width: 20, height: 16)
    }
}
