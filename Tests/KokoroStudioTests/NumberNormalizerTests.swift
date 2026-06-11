import XCTest
@testable import KokoroStudio

final class NumberNormalizerTests: XCTestCase {
    func natural(_ text: String) -> String {
        NumberNormalizer.normalize(text, preset: .natural)
    }

    func testLiteralIsUntouched() {
        let text = "Pay $5.50 for 1–2 items (25%)."
        XCTAssertEqual(NumberNormalizer.normalize(text, preset: .literal), text)
    }

    func testCurrency() {
        XCTAssertEqual(natural("It costs $5."), "It costs 5 dollars.")
        XCTAssertEqual(natural("Add $5.50 now."), "Add 5 dollars and 50 cents now.")
        XCTAssertEqual(natural("Just $1 today."), "Just 1 dollar today.")
    }

    func testPercent() {
        XCTAssertEqual(natural("Scores rose 25% overall."),
                       "Scores rose 25 percent overall.")
    }

    func testRanges() {
        XCTAssertEqual(natural("Read pages 1–2 tonight."),
                       "Read pages 1 to 2 tonight.")
        XCTAssertEqual(natural("Allow 10-15 minutes."),
                       "Allow 10 to 15 minutes.")
    }

    func testISODateSpoken() {
        XCTAssertEqual(natural("Due 2026-06-10 at noon."),
                       "Due June 10th, 2026 at noon.")
    }

    func testUSDateSpoken() {
        XCTAssertEqual(natural("Starts 6/1/2026 sharp."),
                       "Starts June 1st, 2026 sharp.")
    }

    func testTimes() {
        XCTAssertEqual(natural("Meet at 3:30 or 4:05 or 5:00."),
                       "Meet at 3 30 or 4 oh 5 or 5 o'clock.")
    }

    func testSuperscriptsAndDegrees() {
        XCTAssertEqual(natural("Area is x² here."), "Area is x squared here.")
        XCTAssertEqual(natural("Heat to 25°C."), "Heat to 25 degrees Celsius.")
    }

    func testVersions() {
        XCTAssertEqual(natural("Install v1.2 first."),
                       "Install version 1 point 2 first.")
        XCTAssertEqual(natural("Now on v2.0.1 today."),
                       "Now on version 2 point 0 point 1 today.")
    }

    func testMiscSymbols() {
        XCTAssertEqual(natural("Salt & pepper."), "Salt and pepper.")
        XCTAssertEqual(natural("A 3×4 grid."), "A 3 times 4 grid.")
        XCTAssertEqual(natural("See item #5 below."), "See item number 5 below.")
        XCTAssertEqual(natural("Use ½ cup."), "Use one half cup.")
    }
}
