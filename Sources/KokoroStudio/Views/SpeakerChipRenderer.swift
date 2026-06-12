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
        guard let textView else { return }
        if enabled { installPillLayoutManagerIfNeeded(on: textView) }
        guard let lm = textView.layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        let pillManager = lm as? SpeakerChipLayoutManager
        var chips: [(range: NSRange, color: NSColor)] = []
        defer { pillManager?.chips = chips }

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
            // Text gets a contrast-assured variant (WCAG AA 4.5:1 against the
            // pill); the pill itself keeps the full-saturation palette color.
            let textColor = SpeakerIdentity.dynamicChipTextColor(
                colorIndex: style.colorIndex)
            lm.addTemporaryAttribute(.foregroundColor, value: textColor,
                                     forCharacterRange: tagRange)
            chips.append((tagRange, color))
        }
    }

    /// Swap in the pill-drawing layout manager once. The editor already runs
    /// on TextKit 1 (FollowAlongHighlighter touches `layoutManager` too), so
    /// the replacement keeps the same text storage and container.
    private static func installPillLayoutManagerIfNeeded(on textView: NSTextView) {
        guard let container = textView.textContainer,
              !(textView.layoutManager is SpeakerChipLayoutManager) else { return }
        container.replaceLayoutManager(SpeakerChipLayoutManager())
    }
}
