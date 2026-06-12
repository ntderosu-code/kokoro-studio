import AppKit

/// Draws a rounded, tinted background behind `@Name:` tag ranges — the pill
/// look for speaker chips. `SpeakerChipRenderer` feeds it the ranges; this
/// class only draws.
final class SpeakerChipLayoutManager: NSLayoutManager {
    /// Tag ranges (character ranges) and their speaker colors.
    var chips: [(range: NSRange, color: NSColor)] = [] {
        didSet {
            let textLength = textStorage?.length ?? 0
            invalidateDisplay(forCharacterRange: NSRange(location: 0,
                                                         length: textLength))
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange,
                                 at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !chips.isEmpty else { return }
        let visibleChars = characterRange(forGlyphRange: glyphsToShow,
                                          actualGlyphRange: nil)
        let textLength = textStorage?.length ?? 0
        for chip in chips {
            guard NSMaxRange(chip.range) <= textLength,
                  NSIntersectionRange(chip.range, visibleChars).length > 0
            else { continue }
            let glyphRange = self.glyphRange(forCharacterRange: chip.range,
                                             actualCharacterRange: nil)
            guard glyphRange.length > 0,
                  let container = textContainer(forGlyphAt: glyphRange.location,
                                                effectiveRange: nil)
            else { continue }
            var rect = boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            rect = rect.insetBy(dx: -3, dy: 0)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            chip.color.withAlphaComponent(0.28).setFill()
            path.fill()
        }
    }
}
