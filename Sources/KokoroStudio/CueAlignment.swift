import Foundation

/// Maps caption cues back to ranges in the raw editor script (#35). Cue
/// text is post-preprocessing (dictionary and number rewrites), so exact
/// search fails; instead each cue is aligned by greedy in-order word
/// matching with skip tolerance. Sequential by construction — cues are in
/// document order, so the cursor only moves forward.
enum CueAlignment {
    static func align(cues: [String], script: String) -> [NSRange?] {
        let tokens = tokenize(script)
        var results: [NSRange?] = []
        var cursor = 0
        for cue in cues {
            let cueWords = tokenize(cue).map(\.norm)
            guard !cueWords.isEmpty, cursor < tokens.count else {
                results.append(nil)
                continue
            }
            // Anchor on the first (or second) cue word found ahead.
            var start: Int?
            anchorSearch: for anchor in cueWords.prefix(2) {
                for index in cursor..<min(cursor + 300, tokens.count)
                where tokens[index].norm == anchor {
                    start = index
                    break anchorSearch
                }
            }
            guard let startIndex = start else {
                results.append(nil)
                continue
            }
            var matched = 1
            var last = startIndex
            var scriptIndex = startIndex + 1
            for word in cueWords.dropFirst() {
                var lookahead = 0
                var index = scriptIndex
                while index < tokens.count, lookahead < 8 {
                    if tokens[index].norm == word {
                        matched += 1
                        last = index
                        scriptIndex = index + 1
                        break
                    }
                    index += 1
                    lookahead += 1
                }
            }
            // Under half the words matched: too unreliable to highlight.
            guard Double(matched) / Double(cueWords.count) >= 0.5 else {
                results.append(nil)
                continue
            }
            let startLocation = tokens[startIndex].range.location
            let endLocation = tokens[last].range.location + tokens[last].range.length
            results.append(NSRange(location: startLocation,
                                   length: endLocation - startLocation))
            cursor = last + 1
        }
        return results
    }

    /// The cue audible at `time`, nil during spliced pauses or past the end.
    static func cueIndex(at time: Double, cues: [CaptionCue]) -> Int? {
        cues.firstIndex { time >= $0.start && time < $0.end }
    }

    static func tokenize(_ text: String) -> [(norm: String, range: NSRange)] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        return regex.matches(in: text,
                             range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                let norm = ns.substring(with: match.range).lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                guard !norm.isEmpty else { return nil }
                return (norm, match.range)
            }
    }
}
