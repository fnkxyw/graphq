import AppKit
import SketchCore
import SketchRender
import SwiftUI
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG", svg = "SVG", pdf = "PDF"
    var id: String { rawValue }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .svg: .svg
        case .pdf: .pdf
        }
    }
}

struct ExportSheet: View {
    let editor: Editor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var format: ExportFormat = .png
    @State private var scale: CGFloat = 2
    @State private var background = true
    @State private var darkMode = false
    @State private var onlySelected = false
    @State private var preview: NSImage?
    @State private var error: String?

    private var store: SceneStore { editor.store }

    private var elements: [Element] {
        onlySelected && !store.selection.isEmpty ? store.selectedElements : store.elements
    }

    private var options: ExportOptions {
        ExportOptions(scale: format == .png ? scale : 1, includeBackground: background, darkMode: darkMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export").font(.title3.weight(.semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(12)
                }
            }
            .frame(width: 420, height: 220)

            Form {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if format == .png {
                    Picker("Scale", selection: $scale) {
                        Text("1×").tag(CGFloat(1))
                        Text("2×").tag(CGFloat(2))
                        Text("3×").tag(CGFloat(3))
                    }
                    .pickerStyle(.segmented)
                }
                Toggle("Background", isOn: $background)
                Toggle("Dark mode", isOn: $darkMode)
                Toggle("Only selected", isOn: $onlySelected)
                    .disabled(store.selection.isEmpty)
            }
            .formStyle(.columns)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Button("Copy PNG") { copyPNG() }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { export() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 464)
        .onAppear {
            onlySelected = !store.selection.isEmpty
            darkMode = scheme == .dark
            renderPreview()
        }
        .onChange(of: background) { renderPreview() }
        .onChange(of: darkMode) { renderPreview() }
        .onChange(of: onlySelected) { renderPreview() }
    }

    private func renderPreview() {
        var o = options
        o.scale = 1
        guard let img = try? SceneExporter.cgImage(elements, files: store.files, options: o) else { preview = nil; return }
        preview = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
    }

    private func copyPNG() {
        do {
            let png = try SceneExporter.png(elements, files: store.files, options: options)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(png, forType: .png)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        let base = editor.canvas?.window?.title.replacingOccurrences(of: ".graphq", with: "") ?? "Sketch"
        panel.nameFieldStringValue = "\(base).\(format.contentType.preferredFilenameExtension ?? format.rawValue.lowercased())"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch format {
            case .png: data = try SceneExporter.png(elements, files: store.files, options: options)
            case .pdf: data = try SceneExporter.pdf(elements, files: store.files, options: options)
            case .svg: data = Data(try SVGExporter.svg(elements, files: store.files, options: options).utf8)
            }
            try data.write(to: url, options: .atomic)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
