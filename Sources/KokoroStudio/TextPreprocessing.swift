import Foundation

// MARK: - Pronunciation dictionary

enum PronunciationRuleKind: Equatable {
    /// `word = sounds-like` — replace with a phonetic respelling.
    case replace(String)
    /// `word = @letters` — spell out: "APA" reads as "A. P. A".
    case letters
    /// `word = @word` — explicitly say as written (no transformation).
    case word
    /// `word = @letters-first` — spell out the first occurrence only.
    case lettersFirst
}

struct PronunciationRule: Equatable {
    let word: String
    let kind: PronunciationRuleKind
}

enum InlineOverrides {
    /// `{Roush|rowsh}` — one-off respelling at the exact spot it's written,
    /// without a dictionary entry. Applied before the dictionary so explicit
    /// author markup always wins.
    static func apply(to text: String) -> String {
        guard text.contains("{") else { return text }
        guard let regex = try? NSRegularExpression(
            pattern: #"\{([^|{}\n]+)\|([^{}\n]+)\}"#) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: "$2")
    }
}

enum PronunciationDictionary {
    /// Parses rules from text, one per line:
    ///   `word = sounds-like`        respell
    ///   `word = @letters`           spell out (A-P-A)
    ///   `word = @word`              say as written
    ///   `word = @letters-first`     spell out first occurrence, normal after
    /// Blank lines and lines starting with `#` are ignored.
    static func parse(_ text: String) -> [PronunciationRule] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let word = parts[0].trimmingCharacters(in: .whitespaces)
            let replacement = parts[1].trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty, !replacement.isEmpty else { return nil }

            let kind: PronunciationRuleKind
            switch replacement.lowercased() {
            case "@letters": kind = .letters
            case "@word": kind = .word
            case "@letters-first", "@lettersfirst", "@spell-first":
                kind = .lettersFirst
            default:
                kind = .replace(replacement)
            }
            return PronunciationRule(word: word, kind: kind)
        }
    }

    /// "APA" -> "A. P. A", "MP3" -> "M. P. 3" — periods nudge the engine to
    /// read letter names; digits read naturally on their own.
    static func spelledOut(_ word: String) -> String {
        word.map { character in
            character.isLetter ? "\(character.uppercased())." : String(character)
        }
        .joined(separator: " ")
    }

    /// Applies rules to whole-word, case-insensitive occurrences.
    static func apply(_ rules: [PronunciationRule], to text: String) -> String {
        var result = text
        for rule in rules {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: rule.word))\\b"
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]) else { continue }
            let fullRange = NSRange(result.startIndex..., in: result)

            switch rule.kind {
            case .word:
                continue // explicit "say as written"
            case .replace(let replacement):
                result = regex.stringByReplacingMatches(
                    in: result, range: fullRange,
                    withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
            case .letters:
                result = regex.stringByReplacingMatches(
                    in: result, range: fullRange,
                    withTemplate: NSRegularExpression.escapedTemplate(
                        for: spelledOut(rule.word)))
            case .lettersFirst:
                if let match = regex.firstMatch(in: result, range: fullRange),
                   let range = Range(match.range, in: result) {
                    result.replaceSubrange(range, with: spelledOut(rule.word))
                }
            }
        }
        return result
    }
}

// MARK: - Script segmentation for pause control

struct ScriptSegment: Equatable {
    let text: String
    /// Extra silence to insert after this segment, in milliseconds.
    let pauseAfterMs: Int
    /// Speaker tag from `@Name:` lines; nil means the default narrator.
    let speaker: String?

    init(text: String, pauseAfterMs: Int, speaker: String? = nil) {
        self.text = text
        self.pauseAfterMs = pauseAfterMs
        self.speaker = speaker
    }
}

struct PauseSettings: Equatable {
    var paragraphMs = 500
    var sentenceMs = 0   // after . ! ?
    var clauseMs = 0     // after , ; :
    var headingMs = 800  // after lines starting with #

    static let defaultInlineMarkerMs = 600
}

enum ScriptSegmenter {
    /// Splits a script into segments so configurable silence can be spliced
    /// between them. Understands:
    ///   - `@Name:` line prefixes — speaker switching (carried on segments)
    ///   - `#` line prefixes — headings (get `pauses.headingMs` after them)
    ///   - `[pause:800]` inline markers — explicit beats anywhere in text
    ///   - sentence (`. ! ?`) and clause (`, ; :`) pause types
    /// With everything at 0 the script passes through whole, preserving the
    /// model's natural prosody. `sentenceSplit` forces sentence-level
    /// segments even with zero pauses, for caption cue granularity.
    static func segment(_ script: String,
                        pauses: PauseSettings,
                        sentenceSplit: Bool = false) -> [ScriptSegment] {
        let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScript.isEmpty else { return [] }

        let lines = trimmedScript
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Fast path: nothing to split on and no markers/tags present.
        let anyPause = pauses.paragraphMs > 0 || pauses.sentenceMs > 0
            || pauses.clauseMs > 0 || pauses.headingMs > 0
        let hasSyntax = trimmedScript.contains("[pause")
            || lines.contains { $0.hasPrefix("@") || $0.hasPrefix("#") }
        if !anyPause && !sentenceSplit && !hasSyntax {
            return [ScriptSegment(text: trimmedScript, pauseAfterMs: 0)]
        }

        var segments: [ScriptSegment] = []
        var currentSpeaker: String?

        for (lineIndex, rawLine) in lines.enumerated() {
            var line = rawLine
            let isLastLine = lineIndex == lines.count - 1

            // Speaker tag: "@Name: rest of line"
            if let match = line.firstMatch(of: #/^@([\w ]+):\s*(.*)$/#) {
                currentSpeaker = String(match.1).trimmingCharacters(in: .whitespaces)
                line = String(match.2)
                if line.isEmpty { continue } // bare tag sets speaker for following lines
            }

            // Heading: "# Section title"
            var isHeading = false
            if line.hasPrefix("#") {
                isHeading = true
                line = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
            }

            let endOfLinePause = isLastLine ? 0
                : (isHeading ? pauses.headingMs : pauses.paragraphMs)

            // Inline pause markers split the line into pieces.
            let pieces = splitInlineMarkers(line)
            for (pieceIndex, piece) in pieces.enumerated() {
                let isLastPiece = pieceIndex == pieces.count - 1
                let pieceEndPause = piece.markerPauseMs
                    ?? (isLastPiece ? endOfLinePause : 0)

                if piece.text.isEmpty {
                    // Marker with no preceding text: attach silence to the
                    // previous segment, or emit a silence-only segment.
                    if pieceEndPause > 0 {
                        segments.append(ScriptSegment(text: "", pauseAfterMs: pieceEndPause,
                                                      speaker: currentSpeaker))
                    }
                    continue
                }

                let chunks = splitByPauseType(piece.text, pauses: pauses,
                                              sentenceSplit: sentenceSplit)
                for (chunkIndex, chunk) in chunks.enumerated() {
                    let isLastChunk = chunkIndex == chunks.count - 1
                    segments.append(ScriptSegment(
                        text: chunk.text,
                        pauseAfterMs: isLastChunk ? pieceEndPause : chunk.pauseAfterMs,
                        speaker: currentSpeaker))
                }
            }
        }
        // Don't pause after the final audible segment.
        if let last = segments.lastIndex(where: { !$0.text.isEmpty }),
           last == segments.count - 1 {
            segments[last] = ScriptSegment(text: segments[last].text,
                                           pauseAfterMs: 0,
                                           speaker: segments[last].speaker)
        }
        return segments
    }

    /// Detects unique speaker names (`@Name:` lines) in script order.
    static func speakerNames(in script: String) -> [String] {
        var names: [String] = []
        for line in script.components(separatedBy: CharacterSet.newlines) {
            if let match = line.trimmingCharacters(in: .whitespaces)
                .firstMatch(of: #/^@([\w ]+):/#) {
                let name = String(match.1).trimmingCharacters(in: .whitespaces)
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    // MARK: - Internals

    private struct MarkerPiece {
        let text: String
        let markerPauseMs: Int? // pause from a [pause:N] marker ending this piece
    }

    /// "Wait[pause:800] now go" -> [("Wait", 800), ("now go", nil)]
    private static func splitInlineMarkers(_ line: String) -> [MarkerPiece] {
        let pattern = #/\[pause(?::\s*(\d+))?\]/#.ignoresCase()
        var pieces: [MarkerPiece] = []
        var remainder = Substring(line)
        while let match = remainder.firstMatch(of: pattern) {
            let before = String(remainder[..<match.range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let pause = match.1.flatMap { Int($0) } ?? PauseSettings.defaultInlineMarkerMs
            pieces.append(MarkerPiece(text: before, markerPauseMs: pause))
            remainder = remainder[match.range.upperBound...]
        }
        let tail = String(remainder).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty || pieces.isEmpty {
            pieces.append(MarkerPiece(text: tail, markerPauseMs: nil))
        }
        return pieces
    }

    private struct PauseChunk {
        let text: String
        let pauseAfterMs: Int
    }

    /// Splits text by the pause types that are enabled and assigns each
    /// chunk the pause matching its terminal punctuation.
    private static func splitByPauseType(_ text: String, pauses: PauseSettings,
                                         sentenceSplit: Bool) -> [PauseChunk] {
        var splitCharacters: Set<Character> = []
        if pauses.sentenceMs > 0 || sentenceSplit {
            splitCharacters.formUnion(sentencePunctuation)
        }
        if pauses.clauseMs > 0 {
            splitCharacters.formUnion(clausePunctuation)
        }
        guard !splitCharacters.isEmpty else {
            return [PauseChunk(text: text, pauseAfterMs: 0)]
        }
        return splitAtPunctuation(text, characters: splitCharacters).map { chunk in
            let pause: Int
            if let last = chunk.last, sentencePunctuation.contains(last) {
                pause = pauses.sentenceMs
            } else if let last = chunk.last, clausePunctuation.contains(last) {
                pause = pauses.clauseMs
            } else {
                pause = 0
            }
            return PauseChunk(text: chunk, pauseAfterMs: pause)
        }
    }

    private static let clausePunctuation: Set<Character> = [";", ":", ","]
    private static let sentencePunctuation: Set<Character> = [".", "!", "?"]

    /// Splits at the given punctuation, keeping it attached to the preceding
    /// text. "Hello, world." with clause punctuation -> ["Hello,", "world."]
    private static func splitAtPunctuation(_ text: String,
                                           characters punctuation: Set<Character>) -> [String] {
        var clauses: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if punctuation.contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { clauses.append(trimmed) }
                current = ""
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty { clauses.append(remainder) }
        // Merge fragments that are pure punctuation (e.g. from "..." runs).
        return clauses.reduce(into: [String]()) { merged, clause in
            if clause.allSatisfy({ punctuation.contains($0) }), !merged.isEmpty {
                merged[merged.count - 1] += clause
            } else {
                merged.append(clause)
            }
        }
    }
}
