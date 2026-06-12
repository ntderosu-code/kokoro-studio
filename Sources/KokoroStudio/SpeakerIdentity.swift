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

    /// Resolve a speaker to its style, honoring overrides, else auto-assigning.
    static func style(for name: String,
                      colorOverrides: [String: Int],
                      symbolOverrides: [String: Int]) -> Style {
        if name == narratorName {
            return Style(colorIndex: narratorColorIndex, symbolIndex: narratorSymbolIndex)
        }
        let auto = nextFreeStyle(usedColors: Array(colorOverrides.values),
                                 usedSymbols: Array(symbolOverrides.values))
        return Style(colorIndex: colorOverrides[name] ?? auto.colorIndex,
                     symbolIndex: symbolOverrides[name] ?? auto.symbolIndex)
    }

    /// Lowest palette slot not already used; wraps modulo when full.
    static func nextFreeStyle(usedColors: [Int], usedSymbols: [Int]) -> Style {
        Style(colorIndex: lowestFree(in: usedColors),
              symbolIndex: lowestFree(in: usedSymbols))
    }

    private static func lowestFree(in used: [Int]) -> Int {
        let set = Set(used)
        for i in 0..<paletteCount where !set.contains(i) { return i }
        return (used.max() ?? -1).advanced(by: 1) % paletteCount
    }

    /// Display color for a resolved style (handles the narrator sentinel).
    static func displayColor(colorIndex: Int) -> NSColor {
        colorIndex < 0 ? narratorColor : colors[colorIndex % colors.count]
    }

    /// SF Symbol name for a resolved style (handles the narrator sentinel).
    static func displaySymbol(symbolIndex: Int) -> String {
        symbolIndex < 0 ? narratorSymbolName : symbolNames[symbolIndex % symbolNames.count]
    }
}
