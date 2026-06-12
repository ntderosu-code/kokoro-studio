import XCTest
@testable import KokoroStudio

final class SpeakerIdentityTests: XCTestCase {
    func testNarratorHasFixedStyle() {
        let style = SpeakerIdentity.style(for: "Narrator",
                                          colorOverrides: [:], symbolOverrides: [:])
        XCTAssertEqual(style.colorIndex, SpeakerIdentity.narratorColorIndex)
        XCTAssertEqual(style.symbolIndex, SpeakerIdentity.narratorSymbolIndex)
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
        let style = SpeakerIdentity.style(for: "Alex",
                                          colorOverrides: ["Alex": 5],
                                          symbolOverrides: ["Alex": 3])
        XCTAssertEqual(style.colorIndex, 5)
        XCTAssertEqual(style.symbolIndex, 3)
    }
}
