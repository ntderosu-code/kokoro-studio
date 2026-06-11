import Foundation

/// CSV import/export for the pronunciation dictionary (#29), so course
/// teams can share one set of pronunciations across machines.
/// Columns: term,replacement,mode — replacement is empty unless mode is
/// "replace". Minimal RFC-4180: fields with commas/quotes/newlines are
/// quoted, `""` escapes a quote.
enum DictionaryCSV {
    static let header = "term,replacement,mode"

    struct MergeResult: Equatable {
        var mergedText: String
        var addedCount: Int
        var conflictTerms: [String]
    }

    static func export(rulesText: String) -> String {
        var lines = [header]
        for rule in PronunciationDictionary.parse(rulesText) {
            switch rule.kind {
            case .replace(let replacement):
                lines.append("\(field(rule.word)),\(field(replacement)),replace")
            case .letters:
                lines.append("\(field(rule.word)),,letters")
            case .word:
                lines.append("\(field(rule.word)),,word")
            case .lettersFirst:
                lines.append("\(field(rule.word)),,letters-first")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ csv: String) -> [PronunciationRule] {
        var rules: [PronunciationRule] = []
        for line in csv.components(separatedBy: .newlines) {
            let fields = splitCSVLine(line)
            guard fields.count >= 3 else { continue }
            let term = fields[0].trimmingCharacters(in: .whitespaces)
            let replacement = fields[1].trimmingCharacters(in: .whitespaces)
            let mode = fields[2].trimmingCharacters(in: .whitespaces).lowercased()
            guard !term.isEmpty, term.lowercased() != "term" else { continue }
            switch mode {
            case "letters":
                rules.append(PronunciationRule(word: term, kind: .letters))
            case "word":
                rules.append(PronunciationRule(word: term, kind: .word))
            case "letters-first", "lettersfirst":
                rules.append(PronunciationRule(word: term, kind: .lettersFirst))
            case "replace":
                guard !replacement.isEmpty else { continue }
                rules.append(PronunciationRule(word: term,
                                               kind: .replace(replacement)))
            default:
                continue
            }
        }
        return rules
    }

    /// Merges imported rules into the existing rules text. Existing text —
    /// including comments and ordering — is preserved; new terms are
    /// appended in dictionary line format. Terms whose imported rule
    /// differs are reported as conflicts; `preferImported` rewrites those
    /// lines in place.
    static func merge(imported: [PronunciationRule], into existingText: String,
                      preferImported: Bool) -> MergeResult {
        let existingByWord = Dictionary(
            PronunciationDictionary.parse(existingText)
                .map { ($0.word.lowercased(), $0) },
            uniquingKeysWith: { _, last in last })

        var conflicts: [String] = []
        var toAppend: [PronunciationRule] = []
        var appendedKeys = Set<String>()
        var replacements: [String: PronunciationRule] = [:]

        for rule in imported {
            let key = rule.word.lowercased()
            guard let current = existingByWord[key] else {
                if appendedKeys.insert(key).inserted { toAppend.append(rule) }
                continue
            }
            if current.kind == rule.kind { continue }
            conflicts.append(rule.word)
            if preferImported { replacements[key] = rule }
        }

        var lines = existingText.components(separatedBy: "\n")
        if !replacements.isEmpty {
            lines = lines.map { line in
                guard let parsed = PronunciationDictionary.parse(line).first,
                      let replacement = replacements[parsed.word.lowercased()]
                else { return line }
                return ruleLine(replacement)
            }
        }
        var mergedText = lines.joined(separator: "\n")
        if !toAppend.isEmpty {
            if !mergedText.isEmpty, !mergedText.hasSuffix("\n") {
                mergedText += "\n"
            }
            mergedText += toAppend.map(ruleLine).joined(separator: "\n") + "\n"
        }
        return MergeResult(mergedText: mergedText, addedCount: toAppend.count,
                           conflictTerms: conflicts)
    }

    /// A rule in dictionary text format, e.g. "APA = @letters".
    static func ruleLine(_ rule: PronunciationRule) -> String {
        switch rule.kind {
        case .replace(let replacement): return "\(rule.word) = \(replacement)"
        case .letters: return "\(rule.word) = @letters"
        case .word: return "\(rule.word) = @word"
        case .lettersFirst: return "\(rule.word) = @letters-first"
        }
    }

    // MARK: - CSV plumbing

    private static func field(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(line)
        var i = 0
        while i < characters.count {
            let character = characters[i]
            if inQuotes {
                if character == "\"" {
                    if i + 1 < characters.count, characters[i + 1] == "\"" {
                        current.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            i += 1
        }
        fields.append(current)
        return fields
    }
}
