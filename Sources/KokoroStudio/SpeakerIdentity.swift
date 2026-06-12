import AppKit

/// Visual identity (color + SF Symbol) for a speaker in margin mode.
/// Pure data + deterministic slot assignment; no app state.
enum SpeakerIdentity {
    struct Style: Equatable {
        let colorIndex: Int
        let symbolIndex: Int
    }

    /// SF Symbol names, one per palette slot.
    static let symbolNames = [
        "circle.fill", "diamond.fill", "triangle.fill", "square.fill",
        "hexagon.fill", "star.fill", "seal.fill", "drop.fill",
    ]

    /// Palette colors, index-aligned with `symbolNames`.
    static let colors: [NSColor] = [
        .systemBlue, .systemOrange, .systemGreen, .systemPurple,
        .systemPink, .systemTeal, .systemYellow, .systemRed,
    ]

    static var paletteCount: Int { symbolNames.count }

    static let narratorName = "Narrator"
    static let narratorColorIndex = -1   // sentinel: render gray
    static let narratorSymbolIndex = -1  // sentinel: render "text.alignleft"

    static let narratorColor = NSColor.systemGray
    static let narratorSymbolName = "text.alignleft"

    /// Resolve every speaker to a distinct style in one pass, in order of
    /// appearance. Overrides win, and the slots they occupy are skipped
    /// when auto-assigning the remaining speakers — so speakers without an
    /// override still come out visually distinct from each other.
    static func styles(for speakers: [String],
                       colorOverrides: [String: Int],
                       symbolOverrides: [String: Int]) -> [String: Style] {
        var resolved: [String: Style] = [:]
        var usedColors = Array(colorOverrides.values)
        var usedSymbols = Array(symbolOverrides.values)
        for name in speakers where resolved[name] == nil {
            if name == narratorName {
                resolved[name] = Style(colorIndex: narratorColorIndex,
                                       symbolIndex: narratorSymbolIndex)
                continue
            }
            let style = Style(
                colorIndex: colorOverrides[name] ?? lowestFree(in: usedColors),
                symbolIndex: symbolOverrides[name] ?? lowestFree(in: usedSymbols))
            resolved[name] = style
            usedColors.append(style.colorIndex)
            usedSymbols.append(style.symbolIndex)
        }
        return resolved
    }

    /// Lowest palette slot not already used; wraps round-robin when full.
    static func nextFreeStyle(usedColors: [Int], usedSymbols: [Int]) -> Style {
        Style(colorIndex: lowestFree(in: usedColors),
              symbolIndex: lowestFree(in: usedSymbols))
    }

    private static func lowestFree(in used: [Int]) -> Int {
        let set = Set(used)
        for i in 0..<paletteCount where !set.contains(i) { return i }
        return used.count % paletteCount
    }

    /// Display color for a resolved style (handles the narrator sentinel).
    static func displayColor(colorIndex: Int) -> NSColor {
        colorIndex < 0 ? narratorColor : colors[colorIndex % colors.count]
    }

    /// SF Symbol name for a resolved style (handles the narrator sentinel).
    static func displaySymbol(symbolIndex: Int) -> String {
        symbolIndex < 0 ? narratorSymbolName : symbolNames[symbolIndex % symbolNames.count]
    }

    // MARK: - WCAG contrast (issue #41)

    /// Alpha the editor uses when it fills the pill behind a chip.
    static let chipBackgroundAlpha: CGFloat = 0.28

    /// WCAG 2.x relative luminance of a color in sRGB.
    static func relativeLuminance(of color: NSColor) -> CGFloat {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92
                               : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
             + 0.7152 * linear(srgb.greenComponent)
             + 0.0722 * linear(srgb.blueComponent)
    }

    /// WCAG contrast ratio between two colors (1...21).
    static func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let lumA = relativeLuminance(of: first)
        let lumB = relativeLuminance(of: second)
        return (max(lumA, lumB) + 0.05) / (min(lumA, lumB) + 0.05)
    }

    /// The effective pill fill behind a chip: the speaker color at
    /// `chipBackgroundAlpha` composited over the editor background.
    static func chipBackground(colorIndex: Int, over editorBackground: NSColor) -> NSColor {
        let base = editorBackground.usingColorSpace(.sRGB) ?? editorBackground
        let tint = displayColor(colorIndex: colorIndex).usingColorSpace(.sRGB)
        guard let tint else { return base }
        return base.blended(withFraction: chipBackgroundAlpha, of: tint) ?? base
    }

    /// The speaker color, darkened (light mode) or lightened (dark mode)
    /// just enough to hit WCAG AA 4.5:1 against the chip pill it sits on.
    static func chipTextColor(colorIndex: Int, over editorBackground: NSColor) -> NSColor {
        let background = chipBackground(colorIndex: colorIndex, over: editorBackground)
        let base = displayColor(colorIndex: colorIndex).usingColorSpace(.sRGB)
            ?? displayColor(colorIndex: colorIndex)
        return contrastAdjusted(base, against: background, minimumRatio: 4.5)
    }

    /// Chip text color that re-resolves per appearance, for use in views.
    static func dynamicChipTextColor(colorIndex: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            var editorBackground = NSColor.white
            appearance.performAsCurrentDrawingAppearance {
                editorBackground = NSColor.textBackgroundColor
                    .usingColorSpace(.sRGB) ?? .white
            }
            return chipTextColor(colorIndex: colorIndex, over: editorBackground)
        }
    }

    /// Symbol color for a solid speaker-color fill (gutter icons, picker
    /// swatches): white when it clears the 3:1 non-text minimum, else black
    /// (the light fills — yellow, teal — where white washes out).
    static func iconForeground(on fill: NSColor) -> NSColor {
        contrastRatio(fill, .white) >= 3.0 ? .white : .black
    }

    /// Blends `base` toward black or white — whichever direction gains
    /// contrast against `background` — until it meets `minimumRatio`.
    private static func contrastAdjusted(_ base: NSColor,
                                         against background: NSColor,
                                         minimumRatio: CGFloat) -> NSColor {
        if contrastRatio(base, background) >= minimumRatio { return base }
        let backgroundIsLight = relativeLuminance(of: background) > 0.4
        let target: NSColor = backgroundIsLight ? .black : .white
        var fraction: CGFloat = 0.05
        while fraction < 1.0 {
            if let blended = base.blended(withFraction: fraction, of: target),
               contrastRatio(blended, background) >= minimumRatio {
                return blended
            }
            fraction += 0.05
        }
        return target
    }
}
