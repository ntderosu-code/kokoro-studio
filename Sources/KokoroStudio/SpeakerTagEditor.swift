import Foundation

/// Produces the minimal text edit to assign a speaker to a paragraph,
/// keeping `@Speaker:` tags only where the speaker actually changes.
/// Pure logic — returns a range replacement for the caller to apply.
enum SpeakerTagEditor {
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
    }

    static func assign(script: String, paragraphIndex: Int, to speaker: String) -> Edit? {
        let spans = ParagraphSpeakers.resolve(script: script)
        guard spans.indices.contains(paragraphIndex) else { return nil }
        let span = spans[paragraphIndex]
        let ns = script as NSString

        let inherited = paragraphIndex == 0
            ? ParagraphSpeakers.narratorName
            : spans[paragraphIndex - 1].speaker

        // First line of the paragraph (content range + terminator).
        let firstLineRange = ns.lineRange(
            for: NSRange(location: span.range.location, length: 0))
        let firstLine = ns.substring(with: firstLineRange)
        let firstLineNoNewline = firstLine.trimmingCharacters(in: .newlines)
        let inlineText: String? = {
            guard span.hasLiteralTag,
                  let match = firstLineNoNewline.firstMatch(of: #/^@([\w ]+):\s*(.*)$/#)
            else { return nil }
            let rest = String(match.2)
            return rest.isEmpty ? nil : rest
        }()

        if speaker == inherited {
            guard span.hasLiteralTag else {
                return Edit(range: NSRange(location: span.range.location, length: 0),
                            replacement: "") // no-op
            }
            if let inlineText {
                // Drop just the "@Name: " prefix, keep the spoken text.
                let terminator = firstLine.hasSuffix("\n") ? "\n" : ""
                return Edit(range: firstLineRange, replacement: inlineText + terminator)
            }
            // Bare tag line: remove it entirely.
            return Edit(range: firstLineRange, replacement: "")
        }

        // speaker != inherited
        if span.hasLiteralTag {
            let replacementLine = inlineText.map { "@\(speaker): \($0)" } ?? "@\(speaker):"
            // Preserve the original terminator (newline or end-of-string).
            let terminator = firstLine.hasSuffix("\n") ? "\n" : ""
            return Edit(range: firstLineRange, replacement: replacementLine + terminator)
        }
        return Edit(range: NSRange(location: span.range.location, length: 0),
                    replacement: "@\(speaker):\n")
    }
}
