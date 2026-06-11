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

    /// Word/RTF conversion. Headings aren't exposed as named styles by
    /// NSAttributedString, so a paragraph noticeably larger than the
    /// document's body size is treated as a heading. Bold runs inside
    /// normal paragraphs become *emphasis*.
    static func convertAttributed(_ attributed: NSAttributedString) -> String {
        let full = attributed.string as NSString
        var paragraphRanges: [NSRange] = []
        full.enumerateSubstrings(in: NSRange(location: 0, length: full.length),
                                 options: [.byParagraphs, .substringNotRequired]) {
            _, range, _, _ in
            paragraphRanges.append(range)
        }

        func dominantSize(_ range: NSRange) -> CGFloat {
            var weighted: [CGFloat: Int] = [:]
            attributed.enumerateAttribute(.font, in: range) { value, runRange, _ in
                let size = (value as? NSFont)?.pointSize ?? 12
                weighted[size, default: 0] += runRange.length
            }
            return weighted.max { $0.value < $1.value }?.key ?? 12
        }

        let sizes = paragraphRanges.map(dominantSize)
        // Body size = the most common paragraph size across the document.
        var sizeCounts: [CGFloat: Int] = [:]
        for size in sizes { sizeCounts[size, default: 0] += 1 }
        let bodySize = sizeCounts.max { $0.value < $1.value }?.key ?? 12

        var lines: [String] = []
        for (index, range) in paragraphRanges.enumerated() {
            let plain = normalizePlainText(full.substring(with: range))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if plain.isEmpty { lines.append(""); continue }
            if sizes[index] >= bodySize * 1.15 {
                lines.append("# " + plain)
                continue
            }
            var line = ""
            attributed.enumerateAttribute(.font, in: range) { value, runRange, _ in
                let runText = normalizePlainText(full.substring(with: runRange))
                let isBold = (value as? NSFont)?.fontDescriptor.symbolicTraits
                    .contains(.bold) ?? false
                let trimmed = runText.trimmingCharacters(in: .whitespacesAndNewlines)
                if isBold, !trimmed.isEmpty {
                    line += runText.replacingOccurrences(of: trimmed,
                                                         with: "*\(trimmed)*")
                } else {
                    line += runText
                }
            }
            lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func importFile(at url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return convertMarkdown(try String(contentsOf: url, encoding: .utf8))
        case "rtf":
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
            return convertAttributed(attributed)
        case "docx":
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil)
            return convertAttributed(attributed)
        default:
            return normalizePlainText(try String(contentsOf: url, encoding: .utf8))
        }
    }

    static let importableExtensions: Set<String> = ["md", "markdown", "txt",
                                                    "text", "rtf", "docx"]

    static var importableTypes: [UTType] {
        var types: [UTType] = [.plainText, .rtf]
        for ext in ["md", "docx"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }
}
