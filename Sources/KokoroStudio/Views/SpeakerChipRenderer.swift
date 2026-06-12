import AppKit

/// Tints `@Name:` tag ranges in the editor with each speaker's color via
/// layout-manager temporary attributes. Never edits the text or undo stack.
@MainActor
enum SpeakerChipRenderer {
    /// Apply (or, when `enabled` is false, clear) chip styling for `script`.
    static func apply(enabled: Bool,
                      script: String,
                      colorOverrides: [String: Int],
                      symbolOverrides: [String: Int],
                      in textView: NSTextView?) {
        guard let textView, let lm = textView.layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

        guard enabled else { return }
        let ns = script as NSString
        for span in ParagraphSpeakers.resolve(script: script) where span.hasLiteralTag {
            let lineRange = ns.lineRange(
                for: NSRange(location: span.range.location, length: 0))
            let line = ns.substring(with: lineRange)
            guard let match = line.firstMatch(of: #/^@([\w ]+):/#) else { continue }
            let tagLength = line.distance(from: match.0.startIndex, to: match.0.endIndex)
            let tagRange = NSRange(location: lineRange.location, length: tagLength)
            guard NSMaxRange(tagRange) <= ns.length else { continue }
            let style = SpeakerIdentity.style(for: span.speaker,
                                              colorOverrides: colorOverrides,
                                              symbolOverrides: symbolOverrides)
            let color = SpeakerIdentity.displayColor(colorIndex: style.colorIndex)
            lm.addTemporaryAttribute(.foregroundColor, value: color,
                                     forCharacterRange: tagRange)
        }
    }
}
