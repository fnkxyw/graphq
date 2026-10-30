import Foundation

public enum DocumentCodecError: Error, LocalizedError, Equatable {
    case notAGraphqFile
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .notAGraphqFile: "The file is not a graphq document."
        case .unsupportedVersion(let v):
            "This document was created by a newer version of graphq (schema \(v))."
        }
    }
}

/// Reads/writes the `.graphq` JSON format.
///
/// Layout: `{ "type": "graphq", "schemaVersion": N, "elements": [...], "files": {...}, "settings": {...} }`.
/// Older schema versions are upgraded step by step on the raw JSON before decoding,
/// so model types only ever need to understand the current schema.
public enum DocumentCodec {
    public static let currentSchemaVersion = 1
    public static let typeTag = "graphq"
    /// Tag written by pre-rename builds; still accepted on read.
    static let legacyTypeTags: Set<String> = ["sketchboard"]

    /// JSON migration from schema `N` to `N + 1`, keyed by `N`.
    public typealias Migration = @Sendable ([String: Any]) throws -> [String: Any]

    /// Register a migration here whenever `currentSchemaVersion` is bumped.
    static let migrations: [Int: Migration] = [:]

    struct FileEnvelope: Codable {
        var type: String
        var schemaVersion: Int
        var elements: [Element]
        var files: [String: FilePayload]
        var settings: SceneSettings?
    }

    struct FilePayload: Codable {
        var mimeType: String
        /// Base64-encoded bytes.
        var data: String
    }

    public static func encode(_ scene: SceneData, prettyPrinted: Bool = false) throws -> Data {
        let files = scene.prunedFiles().mapValues { FilePayload(mimeType: $0.mimeType, data: $0.data.base64EncodedString()) }
        let envelope = FileEnvelope(type: typeTag, schemaVersion: currentSchemaVersion,
                                    elements: scene.elements, files: files, settings: scene.settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> SceneData {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocumentCodecError.notAGraphqFile
        }
        if let type = json["type"] as? String, type != typeTag, !legacyTypeTags.contains(type) { throw DocumentCodecError.notAGraphqFile }
        // Files without a version predate versioning and are treated as v1.
        var version = json["schemaVersion"] as? Int ?? 1
        if version > currentSchemaVersion { throw DocumentCodecError.unsupportedVersion(version) }
        while version < currentSchemaVersion {
            guard let migrate = migrations[version] else { throw DocumentCodecError.unsupportedVersion(version) }
            json = try migrate(json)
            version += 1
            json["schemaVersion"] = version
        }
        json["type"] = typeTag
        json["schemaVersion"] = version
        if json["files"] == nil { json["files"] = [String: Any]() }
        let normalized = try JSONSerialization.data(withJSONObject: json)
        let envelope = try JSONDecoder().decode(FileEnvelope.self, from: normalized)
        var files: [String: BinaryFile] = [:]
        for (id, payload) in envelope.files {
            guard let bytes = Data(base64Encoded: payload.data) else { continue }
            files[id] = BinaryFile(id: id, mimeType: payload.mimeType, data: bytes)
        }
        var elements = envelope.elements
        ArrowBinding.cleanup(in: &elements)
        return SceneData(elements: elements, files: files, settings: envelope.settings ?? SceneSettings())
    }
}
