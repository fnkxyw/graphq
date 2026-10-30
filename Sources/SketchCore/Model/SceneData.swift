import Foundation

/// Binary attachment (images) referenced by `Element.fileId`.
public struct BinaryFile: Codable, Hashable, Sendable {
    public var id: String
    public var mimeType: String
    public var data: Data

    public init(id: String, mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }

    /// Content-addressed id so pasting the same image twice stores it once.
    public static func makeId(for data: Data) -> String {
        // FNV-1a 64 — stable, dependency-free, good enough for dedup keys.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx-%llx", hash, UInt64(data.count))
    }
}

/// Per-document settings persisted alongside the elements.
public struct SceneSettings: Codable, Hashable, Sendable {
    public var gridEnabled: Bool = false

    public init(gridEnabled: Bool = false) { self.gridEnabled = gridEnabled }
}

/// The whole persisted document content. Element order is z-order (back to front).
public struct SceneData: Hashable, Sendable {
    public var elements: [Element]
    public var files: [String: BinaryFile]
    public var settings: SceneSettings

    public init(elements: [Element] = [], files: [String: BinaryFile] = [:], settings: SceneSettings = .init()) {
        self.elements = elements
        self.files = files
        self.settings = settings
    }

    /// Drops files that are no longer referenced by any element.
    public func prunedFiles() -> [String: BinaryFile] {
        let used = Set(elements.compactMap(\.fileId))
        return files.filter { used.contains($0.key) }
    }
}
