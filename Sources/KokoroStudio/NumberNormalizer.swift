import Foundation

enum NumberPreset: String, CaseIterable, Identifiable {
    case literal, natural
    var id: String { rawValue }
    var label: String { self == .literal ? "Literal" : "Natural" }
}

/// Expands numbers and symbols with read-aloud ambiguity before synthesis.
/// "Literal" leaves text untouched; "Natural" applies the rules below.
/// Digits are left as digits — the engine reads them well; symbols are the
/// problem ("1–2", "25%", "$5.50", "x²", "v1.2", "°C").
enum NumberNormalizer {
    static func normalize(_ text: String, preset: NumberPreset) -> String {
        guard preset == .natural else { return text }
        var result = text

        func replace(_ pattern: String, _ template: String,
                     options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: options) else { return }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: template)
        }

        // Versions: v1.2.3 -> "version 1 point 2 point 3" (before currency
        // and ranges so the dots don't get other readings).
        if let versionRegex = try? NSRegularExpression(
            pattern: #"\bv(\d+(?:\.\d+)+)\b"#, options: [.caseInsensitive]) {
            while let match = versionRegex.firstMatch(
                in: result, range: NSRange(result.startIndex..., in: result)),
                let full = Range(match.range, in: result),
                let digits = Range(match.range(at: 1), in: result) {
                let spoken = "version " + result[digits]
                    .replacingOccurrences(of: ".", with: " point ")
                result.replaceSubrange(full, with: spoken)
            }
        }

        // Currency: $5.50 -> "5 dollars and 50 cents", $1 -> "1 dollar".
        replace(#"\$(\d+)\.(\d{2})\b"#, "$1 dollars and $2 cents")
        replace(#"\$1\b(?!\s*(dollars|dollar))"#, "1 dollar")
        replace(#"\$(\d+)\b"#, "$1 dollars")

        // Percent.
        replace(#"(\d)\s*%"#, "$1 percent")

        // Ranges: en/em dash always; plain hyphen only for short numbers
        // (avoids mangling ISO dates like 2026-06-10).
        replace(#"(\d)\s*[–—]\s*(\d)"#, "$1 to $2")
        replace(#"(?<![\d-])(\d{1,3})-(\d{1,3})(?![\d-])"#, "$1 to $2")

        // Superscripts.
        replace(#"²"#, " squared")
        replace(#"³"#, " cubed")

        // Unicode fractions.
        replace(#"½"#, "one half")
        replace(#"¼"#, "one quarter")
        replace(#"¾"#, "three quarters")

        // Degrees.
        replace(#"°\s*C\b"#, " degrees Celsius")
        replace(#"°\s*F\b"#, " degrees Fahrenheit")
        replace(#"°"#, " degrees")

        // Misc symbols.
        replace(#"\s&\s"#, " and ")
        replace(#"(\d)\s*×\s*(\d)"#, "$1 times $2")
        replace(#"(\d)\s*÷\s*(\d)"#, "$1 divided by $2")
        replace(#"#(\d+)\b"#, "number $1")

        // Collapse doubled spaces introduced by replacements.
        replace(#"  +"#, " ")
        return result
    }
}
