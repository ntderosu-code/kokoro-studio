import Foundation

// MARK: - Pronunciation dictionary

struct PronunciationRule: Equatable {
    let word: String
    let replacement: String
}

enum PronunciationDictionary {
    /// Parses rules from text, one per line: `word = sounds-like`.
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
            return PronunciationRule(word: word, replacement: replacement)
        }
    }

    /// Replaces whole-word, case-insensitive occurrences of each rule's word.
    static func apply(_ rules: [PronunciationRule], to text: String) -> String {
        var result = text
        for rule in rules {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: rule.word))\\b"
            guard let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement))
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
    static func segment(_ script: String,
                        paragraphPauseMs: Int,
                        punctuationPauseMs: Int) -> [ScriptSegment] {
        let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedScript.isEmpty else { return [] }
        guard paragraphPauseMs > 0 || punctuationPauseMs > 0 else {
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
                let clauses = splitAtPunctuation(paragraph)
                for (clauseIndex, clause) in clauses.enumerated() {
                    let isLastClause = clauseIndex == clauses.count - 1
                    segments.append(ScriptSegment(
                        text: clause,
                        pauseAfterMs: isLastClause ? paragraphPause : punctuationPauseMs))
                }
            } else {
                segments.append(ScriptSegment(text: paragraph,
                                              pauseAfterMs: paragraphPause))
            }
        }
        return segments
    }

    /// Splits at `. ! ? ; : ,` keeping the punctuation attached to the
    /// preceding clause. "Hello, world." -> ["Hello,", "world."]
    private static func splitAtPunctuation(_ text: String) -> [String] {
        let punctuation: Set<Character> = [".", "!", "?", ";", ":", ","]
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
