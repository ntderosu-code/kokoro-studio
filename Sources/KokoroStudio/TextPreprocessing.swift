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
}

enum ScriptSegmenter {
    /// Splits a script into segments so configurable silence can be spliced
    /// between them. With both pauses at 0 the script passes through as a
    /// single segment, preserving the model's natural prosody.
    /// `sentenceSplit` forces sentence-level segments even with zero pauses —
    /// used so caption cues land per sentence.
    static func segment(_ script: String,
                        paragraphPauseMs: Int,
                        punctuationPauseMs: Int,
                        sentenceSplit: Bool = false) -> [ScriptSegment] {
        let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScript.isEmpty else { return [] }
        guard paragraphPauseMs > 0 || punctuationPauseMs > 0 || sentenceSplit else {
            return [ScriptSegment(text: trimmedScript, pauseAfterMs: 0)]
        }

        let paragraphs = trimmedScript
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var segments: [ScriptSegment] = []
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let isLastParagraph = paragraphIndex == paragraphs.count - 1
            let paragraphPause = isLastParagraph ? 0 : paragraphPauseMs

            if punctuationPauseMs > 0 {
                let clauses = splitAtPunctuation(paragraph, characters: clausePunctuation)
                for (clauseIndex, clause) in clauses.enumerated() {
                    let isLastClause = clauseIndex == clauses.count - 1
                    segments.append(ScriptSegment(
                        text: clause,
                        pauseAfterMs: isLastClause ? paragraphPause : punctuationPauseMs))
                }
            } else if sentenceSplit {
                let sentences = splitAtPunctuation(paragraph, characters: sentencePunctuation)
                for (sentenceIndex, sentence) in sentences.enumerated() {
                    let isLastSentence = sentenceIndex == sentences.count - 1
                    segments.append(ScriptSegment(
                        text: sentence,
                        pauseAfterMs: isLastSentence ? paragraphPause : 0))
                }
            } else {
                segments.append(ScriptSegment(text: paragraph,
                                              pauseAfterMs: paragraphPause))
            }
        }
        return segments
    }

    private static let clausePunctuation: Set<Character> = [".", "!", "?", ";", ":", ","]
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
