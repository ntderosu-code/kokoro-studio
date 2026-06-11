import Foundation

/// One saved script in the library (#34). Text lives in `<id>.txt`,
/// metadata in a `<id>.json` sidecar, so scripts stay greppable plain text.
struct ScriptDocumentMeta: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    /// True once the user renames explicitly; auto-titling stops then.
    var customTitle = false
    var profileName: String?
    var createdAt = Date()
    var updatedAt = Date()

    init(title: String) {
        self.title = title
    }

    /// Title derived from the first non-empty line, headings unwrapped.
    static func autoTitle(for text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let unwrapped = firstLine.drop { $0 == "#" }
            .trimmingCharacters(in: .whitespaces)
        return unwrapped.isEmpty ? "Untitled" : String(unwrapped.prefix(40))
    }
}

enum DocumentStore {
    /// Tests point this at a temp directory.
    static var directoryOverride: URL?

    static var directory: URL {
        directoryOverride
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
                .appendingPathComponent("Kokoro Studio/Scripts")
    }

    static func list() -> [ScriptDocumentMeta] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ScriptDocumentMeta.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func loadText(id: UUID) -> String {
        (try? String(contentsOf: textURL(id: id), encoding: .utf8)) ?? ""
    }

    static func save(meta: ScriptDocumentMeta, text: String) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try text.write(to: textURL(id: meta.id), atomically: true, encoding: .utf8)
        try saveMeta(meta)
    }

    static func saveMeta(_ meta: ScriptDocumentMeta) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try encoder.encode(meta).write(to: metaURL(id: meta.id))
    }

    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: textURL(id: id))
        try? FileManager.default.removeItem(at: metaURL(id: id))
    }

    static func duplicate(id: UUID) -> ScriptDocumentMeta? {
        guard let original = list().first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.title = original.title + " copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        do {
            try save(meta: copy, text: loadText(id: id))
            return copy
        } catch {
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func textURL(id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("txt")
    }

    private static func metaURL(id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
