import Foundation
import SketchCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTExportedTypeDeclarations).
    static let graphq = UTType(exportedAs: "app.graphq.document", conformingTo: .json)
    /// Files from pre-rename builds (`.sketchboard`); read-only.
    static let legacySketchboard = UTType(importedAs: "app.sketchboard.document", conformingTo: .json)
    /// Declared in Info.plist (UTImportedTypeDeclarations).
    static let excalidraw = UTType(importedAs: "com.excalidraw.document", conformingTo: .json)
}

/// Document wrapper. Reading/writing happens off the main actor and only touches
/// value-type `SceneData`; the live, main-actor `SceneStore` is created from it.
final class SketchDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = SceneData

    static var readableContentTypes: [UTType] { [.graphq, .legacySketchboard, .excalidraw] }
    static var writableContentTypes: [UTType] { [.graphq] }

    private let initialData: SceneData
    /// Created lazily on the main actor (document init may run on a background thread).
    @MainActor private var _store: SceneStore?

    /// Latest committed content. AppKit asks for snapshots from background threads
    /// during autosave, so saving reads this lock-protected copy instead of the store.
    private let lock = NSLock()
    private var latest: SceneData

    @MainActor var store: SceneStore {
        if let s = _store { return s }
        let s = SceneStore(data: initialData)
        s.onCommit = { [weak self] data in self?.publish(data) }
        _store = s
        return s
    }

    private func publish(_ data: SceneData) {
        lock.lock()
        latest = data
        lock.unlock()
    }

    init() {
        initialData = SceneData()
        latest = initialData
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if configuration.contentType.conforms(to: .excalidraw) || ExcalidrawImporter.isExcalidraw(data) {
            initialData = try ExcalidrawImporter.importScene(data)
        } else {
            initialData = try DocumentCodec.decode(data)
        }
        latest = initialData
    }

    func snapshot(contentType: UTType) throws -> SceneData {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func fileWrapper(snapshot: SceneData, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try DocumentCodec.encode(snapshot))
    }
}
