import Foundation

/// A named snapshot of every narration setting, so a whole course can lock
/// to one consistent sound.
struct Profile: Codable, Equatable {
    var engineKind: String
    var voiceID: Int
    var pocketVoicePath: String
    var speed: Double
    var paragraphPauseMs: Int
    var sentencePauseMs: Int
    var clausePauseMs: Int
    var headingPauseMs: Int
    var pronunciationRules: String
    var captionFormat: String
    var normalizeLoudness: Bool
    var exportFormat: String
    var speakerVoicesJSON: String
    // Added after v1.1 — optional so older profile files still decode.
    var numberPreset: String? = nil
    // Added after v1.4 — optional so older profile files still decode.
    var loudnessPreset: String? = nil
    var customLoudnessLUFS: Double? = nil
}

enum ProfileStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("Kokoro Studio/Profiles")
    }

    static func list() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return names.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    static func save(_ profile: Profile, name: String) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: url(for: name))
    }

    static func load(name: String) -> Profile? {
        guard let data = try? Data(contentsOf: url(for: name)) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    static func delete(name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    private static func url(for name: String) -> URL {
        // Keep filenames tame.
        let safe = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent(safe).appendingPathExtension("json")
    }
}
