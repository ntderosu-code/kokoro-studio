import Foundation
import AppKit
import UniformTypeIdentifiers

/// Converts imported documents (#33) into script syntax: headings -> `#`,
/// bold -> `*emphasis*`, smart punctuation -> plain equivalents the
/// normalizer understands, lists/quotes/links flattened to spoken text.
enum ScriptImporter {
    static func normalizePlainText(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let replacements: [(String, String)] = [
            ("\u{2018}", "'"), ("\u{2019}", "'"),
            ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("\u{00A0}", " "), ("\u{2026}", "..."),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    static func convertMarkdown(_ text: String) -> String {
        var lines: [String] = []
        var inCodeFence = false
        for rawLine in normalizePlainText(text).components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCodeFence.toggle(); continue }
            if inCodeFence {
                lines.append(line)
                continue
            }
            if line.isEmpty { lines.append(""); continue }
            // Tables and horizontal rules have no spoken equivalent.
            if line.hasPrefix("|") { continue }
            if line.allSatisfy({ "-*_".contains($0) }), line.count >= 3 { continue }
            // Headings: collapse every level to one # — "##" is reserved
            // for the module-split syntax in scripts.
            if let match = line.firstMatch(of: #/^(#{1,6})\s+(.*)$/#) {
                lines.append("# " + String(match.2))
                continue
            }
            if line.hasPrefix(">") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            line = line.replacing(#/^([-*+]|\d+[.)])\s+/#, with: "")
            line = line.replacing(#/!\[[^\]]*\]\([^)]*\)/#, with: "")
            line = line.replacing(#/\[([^\]]+)\]\([^)]*\)/#) { String($0.output.1) }
            // Bold -> emphasis via placeholders so the italic pass below
            // doesn't strip the markers we just produced.
            line = line.replacing(#/\*\*([^*]+)\*\*/#) { "\u{1}\($0.output.1)\u{2}" }
            line = line.replacing(#/__([^_]+)__/#) { "\u{1}\($0.output.1)\u{2}" }
            line = line.replacing(#/\*([^*\n]+)\*/#) { String($0.output.1) }
            line = line.replacing(#/\b_([^_\n]+)_\b/#) { String($0.output.1) }
            line = line.replacingOccurrences(of: "\u{1}", with: "*")
            line = line.replacingOccurrences(of: "\u{2}", with: "*")
            line = line.replacingOccurrences(of: "`", with: "")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
