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

        // ISO dates 2026-06-10 -> "June 10th, 2026" (before ranges eat the
        // hyphens; the range rule already skips date-shaped tokens).
        result = transformMatches(
            in: result, pattern: #"\b(\d{4})-(\d{2})-(\d{2})\b"#) { match in
            spokenDate(match, order: .yearMonthDay) ?? match
        }
        // US dates 6/10/2026 -> "June 10th, 2026".
        result = transformMatches(
            in: result, pattern: #"\b(\d{1,2})/(\d{1,2})/(\d{4})\b"#) { match in
            spokenDate(match, order: .monthDayYear) ?? match
        }

        // Times: 3:00 -> "3 o'clock", 3:05 -> "3 oh 5", 3:30 -> "3 30".
        result = transformMatches(
            in: result, pattern: #"\b(\d{1,2}):([0-5]\d)\b(?!:)"#) { match in
            let parts = match.split(separator: ":")
            guard parts.count == 2, let minute = Int(parts[1]) else { return match }
            let hour = String(parts[0])
            if minute == 0 { return "\(hour) o'clock" }
            if minute < 10 { return "\(hour) oh \(minute)" }
            return "\(hour) \(minute)"
        }

        // Emails: support@school.edu -> "support at school dot edu".
        result = transformMatches(
            in: result,
            pattern: #"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"#) { match in
            match.replacingOccurrences(of: "@", with: " at ")
                 .replacingOccurrences(of: ".", with: " dot ")
        }

        // URLs/domains with common TLDs (bounded list to avoid eating
        // abbreviations like "e.g." or "U.S.").
        result = transformMatches(
            in: result,
            pattern: #"\b(?:https?://)?(?:www\.)?[\w-]+\.(?:com|org|net|edu|gov|io|ai|co|us|uk|ca|dev|app|info)\b(?:/[\w./~-]*)?"#) { match in
            var spoken = match
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            if spoken.hasSuffix("/") { spoken.removeLast() }
            return spoken
                .replacingOccurrences(of: ".", with: " dot ")
                .replacingOccurrences(of: "/", with: " slash ")
        }

        // Misc symbols.
        replace(#"\s&\s"#, " and ")
        replace(#"(\d)\s*×\s*(\d)"#, "$1 times $2")
        replace(#"(\d)\s*÷\s*(\d)"#, "$1 divided by $2")
        replace(#"#(\d+)\b"#, "number $1")

        // Collapse doubled spaces introduced by replacements.
        replace(#"  +"#, " ")
        return result
    }

    private enum DateOrder { case yearMonthDay, monthDayYear }

    private static let monthNames = ["", "January", "February", "March", "April",
                                     "May", "June", "July", "August", "September",
                                     "October", "November", "December"]

    private static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    private static func spokenDate(_ match: String, order: DateOrder) -> String? {
        let parts = match.split { $0 == "-" || $0 == "/" }.compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (year, month, day): (Int, Int, Int)
        switch order {
        case .yearMonthDay: (year, month, day) = (parts[0], parts[1], parts[2])
        case .monthDayYear: (year, month, day) = (parts[2], parts[0], parts[1])
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        return "\(monthNames[month]) \(ordinal(day)), \(year)"
    }

    /// Replaces each regex match with a computed transformation (regex
    /// templates can't transform match contents, e.g. dots inside a URL).
    private static func transformMatches(in text: String, pattern: String,
                                         _ transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive])
        else { return text }
        var result = text
        let matches = regex.matches(in: text,
                                    range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }
}
