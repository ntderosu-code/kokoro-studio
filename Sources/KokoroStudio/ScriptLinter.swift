import Foundation

/// Pre-generation scan for tokens the engine will likely fumble.
enum ScriptLinter {
    /// Words that read fine despite looking like acronyms.
    private static let knownFine: Set<String> = ["OK", "TV", "AM", "PM", "ID",
                                                 "US", "UK", "USA", "FAQ"]

    /// ALL-CAPS tokens (2–6 letters) not covered by a dictionary rule —
    /// candidates for @letters / @word treatment. Script order, deduped.
    static func acronymSuspects(in script: String,
                                coveredBy rules: [PronunciationRule]) -> [String] {
        let covered = Set(rules.map { $0.word.uppercased() })
        guard let regex = try? NSRegularExpression(pattern: #"\b[A-Z]{2,6}\b"#)
        else { return [] }
        var seen = Set<String>()
        var suspects: [String] = []
        let matches = regex.matches(in: script,
                                    range: NSRange(script.startIndex..., in: script))
        for match in matches {
            guard let range = Range(match.range, in: script) else { continue }
            let token = String(script[range])
            guard !knownFine.contains(token), !covered.contains(token),
                  !seen.contains(token) else { continue }
            seen.insert(token)
            suspects.append(token)
        }
        return suspects
    }
}

// MARK: - Module splitting

struct ScriptModule: Equatable {
    let name: String
    let body: String
}

/// Splits one document into named export modules at `## file: name` lines.
enum ModuleSplitter {
    static func split(_ script: String) -> [ScriptModule] {
        var modules: [ScriptModule] = []
        var currentName: String?
        var currentBody: [String] = []

        func flush() {
            let body = currentBody.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                modules.append(ScriptModule(
                    name: currentName ?? "module-\(modules.count + 1)",
                    body: body))
            }
        }

        for line in script.components(separatedBy: CharacterSet.newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.firstMatch(of: #/^##\s*file:\s*(.+)$/#.ignoresCase()) {
                flush()
                currentName = String(match.1).trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        flush()

        if modules.isEmpty {
            return []
        }
        return modules
    }
}
