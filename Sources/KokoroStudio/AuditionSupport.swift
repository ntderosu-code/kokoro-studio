import Foundation

/// One side of an A/B voice comparison (#32): a Kokoro catalog voice or
/// a Supertonic voice style.
enum AuditionVoice: Equatable, Hashable {
    case kokoro(Int)
    case supertonic(Int)

    var label: String {
        switch self {
        case .kokoro(let id): return VoiceCatalog.voice(forID: id).humanName
        case .supertonic(let id):
            return "Supertonic \(SupertonicVoiceCatalog.voice(forID: id).name)"
        }
    }

    /// Stable token for cache keys.
    var cacheLabel: String {
        switch self {
        case .kokoro(let id): return "k\(id)"
        case .supertonic(let id): return "st\(id)"
        }
    }
}

enum AuditionSupport {
    /// Deterministic cache filename component for one (text, voice) render.
    /// djb2 rather than Hasher because Hasher is seeded per-process and
    /// these names end up on disk.
    static func cacheKey(text: String, voiceLabel: String) -> String {
        var hash: UInt64 = 5381
        for byte in Array("\(voiceLabel)|\(text)".utf8) {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    /// What to audition when nothing is selected: the first prose sentence
    /// of the script — headings and speaker tags are skipped so the
    /// comparison plays natural narration.
    static func defaultText(from script: String) -> String {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var line = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? trimmed
        line = line.replacing(#/^@[\w ]+:\s*/#, with: "")
        var sentence = line
        if let end = line.firstIndex(where: { ".!?".contains($0) }) {
            sentence = String(line[...end])
        }
        return String(sentence.prefix(240))
    }
}
