import Foundation

/// Splits a script into paragraph blocks and resolves the effective
/// (sticky) `@Speaker:` for each. Pure logic — no AppKit, no models.
enum ParagraphSpeakers {
    static let narratorName = "Narrator"

    struct Span: Equatable {
        let range: NSRange      // character range of the paragraph in the script
        let speaker: String     // effective speaker name ("Narrator" by default)
        let hasLiteralTag: Bool // first line of the paragraph is an @Name: tag
    }

    static func resolve(script: String) -> [Span] {
        let ns = script as NSString
        var spans: [Span] = []
        var effective = narratorName

        var blockRange: NSRange?
        var blockSpeaker = narratorName
        var blockHasTag = false
        var blockHasFirstLine = false

        func endBlock() {
            if let range = blockRange {
                spans.append(Span(range: range, speaker: blockSpeaker,
                                  hasLiteralTag: blockHasTag))
            }
            blockRange = nil
            blockHasTag = false
            blockHasFirstLine = false
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines]) { line, lineRange, enclosingRange, _ in
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                endBlock()
                return
            }
            var isTagLine = false
            if let match = trimmed.firstMatch(of: #/^@([\w ]+):\s*(.*)$/#) {
                effective = String(match.1).trimmingCharacters(in: .whitespaces)
                isTagLine = true
            }
            if blockRange == nil {
                blockRange = enclosingRange
            } else {
                blockRange = NSUnionRange(blockRange!, enclosingRange)
            }
            if !blockHasFirstLine {
                blockSpeaker = effective
                blockHasTag = isTagLine
                blockHasFirstLine = true
            }
            _ = lineRange
        }
        endBlock()
        return spans
    }
}
