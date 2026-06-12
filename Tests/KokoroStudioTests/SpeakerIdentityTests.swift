import AppKit
import XCTest
@testable import KokoroStudio

final class SpeakerIdentityTests: XCTestCase {
    func testNarratorHasFixedStyle() {
        let styles = SpeakerIdentity.styles(for: ["Narrator"],
                                            colorOverrides: [:], symbolOverrides: [:])
        XCTAssertEqual(styles["Narrator"]?.colorIndex, SpeakerIdentity.narratorColorIndex)
        XCTAssertEqual(styles["Narrator"]?.symbolIndex, SpeakerIdentity.narratorSymbolIndex)
    }

    func testSpeakersGetDistinctStylesInAppearanceOrder() {
        let styles = SpeakerIdentity.styles(for: ["Byron", "Maya", "Sam"],
                                            colorOverrides: [:], symbolOverrides: [:])
        XCTAssertEqual(styles["Byron"], SpeakerIdentity.Style(colorIndex: 0, symbolIndex: 0))
        XCTAssertEqual(styles["Maya"], SpeakerIdentity.Style(colorIndex: 1, symbolIndex: 1))
        XCTAssertEqual(styles["Sam"], SpeakerIdentity.Style(colorIndex: 2, symbolIndex: 2))
    }

    func testOverrideWinsAndItsSlotIsSkippedForAutoAssignment() {
        let styles = SpeakerIdentity.styles(for: ["Byron", "Maya"],
                                            colorOverrides: ["Byron": 0],
                                            symbolOverrides: ["Byron": 0])
        XCTAssertEqual(styles["Byron"], SpeakerIdentity.Style(colorIndex: 0, symbolIndex: 0))
        XCTAssertEqual(styles["Maya"], SpeakerIdentity.Style(colorIndex: 1, symbolIndex: 1))
    }

    func testNarratorDoesNotConsumeAPaletteSlot() {
        let styles = SpeakerIdentity.styles(for: ["Narrator", "Byron"],
                                            colorOverrides: [:], symbolOverrides: [:])
        XCTAssertEqual(styles["Byron"]?.colorIndex, 0)
    }

    func testMoreSpeakersThanPaletteSlotsWrapWithoutPilingOnOneSlot() {
        let names = (0..<10).map { "Speaker\($0)" }
        let styles = SpeakerIdentity.styles(for: names,
                                            colorOverrides: [:], symbolOverrides: [:])
        // 10 speakers over 8 slots: the two wrapped ones reuse different slots.
        XCTAssertEqual(styles["Speaker8"]?.colorIndex, 0)
        XCTAssertEqual(styles["Speaker9"]?.colorIndex, 1)
    }

    func testNextFreeStylePicksLowestUnusedSlot() {
        let next = SpeakerIdentity.nextFreeStyle(usedColors: [0, 1], usedSymbols: [0, 1])
        XCTAssertEqual(next.colorIndex, 2)
        XCTAssertEqual(next.symbolIndex, 2)
    }

    func testNextFreeStyleWrapsWhenPaletteFull() {
        let used = Array(0..<SpeakerIdentity.paletteCount)
        let next = SpeakerIdentity.nextFreeStyle(usedColors: used, usedSymbols: used)
        XCTAssertTrue((0..<SpeakerIdentity.paletteCount).contains(next.colorIndex))
    }

    func testOverrideTakesPrecedence() {
        let styles = SpeakerIdentity.styles(for: ["Alex"],
                                            colorOverrides: ["Alex": 5],
                                            symbolOverrides: ["Alex": 3])
        XCTAssertEqual(styles["Alex"], SpeakerIdentity.Style(colorIndex: 5, symbolIndex: 3))
    }

    // MARK: - WCAG contrast (issue #41)

    /// Light- and dark-mode editor backgrounds the chips sit on.
    private let lightEditorBackground = NSColor.white
    private let darkEditorBackground = NSColor(srgbRed: 0.12, green: 0.12,
                                               blue: 0.12, alpha: 1)

    func testContrastRatioOfBlackOnWhiteIsTwentyOne() {
        let ratio = SpeakerIdentity.contrastRatio(.black, .white)
        XCTAssertEqual(ratio, 21.0, accuracy: 0.1)
    }

    func testChipTextMeetsAAOnLightBackground() {
        for index in -1..<SpeakerIdentity.paletteCount {
            let background = SpeakerIdentity.chipBackground(
                colorIndex: index, over: lightEditorBackground)
            let text = SpeakerIdentity.chipTextColor(
                colorIndex: index, over: lightEditorBackground)
            let ratio = SpeakerIdentity.contrastRatio(text, background)
            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                "palette \(index) light mode: \(ratio)")
        }
    }

    func testChipTextMeetsAAOnDarkBackground() {
        for index in -1..<SpeakerIdentity.paletteCount {
            let background = SpeakerIdentity.chipBackground(
                colorIndex: index, over: darkEditorBackground)
            let text = SpeakerIdentity.chipTextColor(
                colorIndex: index, over: darkEditorBackground)
            let ratio = SpeakerIdentity.contrastRatio(text, background)
            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                "palette \(index) dark mode: \(ratio)")
        }
    }

    func testIconForegroundMeetsNonTextContrastOnEveryFill() {
        for index in -1..<SpeakerIdentity.paletteCount {
            let fill = SpeakerIdentity.displayColor(colorIndex: index)
            let symbol = SpeakerIdentity.iconForeground(on: fill)
            let ratio = SpeakerIdentity.contrastRatio(symbol, fill)
            XCTAssertGreaterThanOrEqual(ratio, 3.0,
                "palette \(index) icon: \(ratio)")
        }
    }

    func testIconForegroundPrefersWhiteWhenWhiteIsLegible() {
        // Black contrasts marginally more on systemBlue, but white still
        // clears 3:1 and is the conventional fill — prefer it.
        let symbol = SpeakerIdentity.iconForeground(on: .systemBlue)
        XCTAssertGreaterThan(SpeakerIdentity.relativeLuminance(of: symbol), 0.5)
    }

    func testIconForegroundIsDarkOnYellow() {
        let yellow = SpeakerIdentity.colors.firstIndex(of: .systemYellow)!
        let symbol = SpeakerIdentity.iconForeground(
            on: SpeakerIdentity.displayColor(colorIndex: yellow))
        XCTAssertLessThan(SpeakerIdentity.relativeLuminance(of: symbol), 0.5)
    }
}
