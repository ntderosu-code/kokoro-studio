import XCTest
@testable import KokoroStudio

final class InlineOverridesTests: XCTestCase {
    func testReplacesAtSite() {
        XCTAssertEqual(InlineOverrides.apply(to: "Dr. {Roush|rowsh} teaches."),
                       "Dr. rowsh teaches.")
    }

    func testMultipleAndUntouched() {
        XCTAssertEqual(InlineOverrides.apply(to: "{a|one} and {b|two} and c"),
                       "one and two and c")
        XCTAssertEqual(InlineOverrides.apply(to: "no braces here"),
                       "no braces here")
    }

    func testMalformedLeftAlone() {
        XCTAssertEqual(InlineOverrides.apply(to: "{nopipe} stays"),
                       "{nopipe} stays")
    }
}

final class URLEmailReadingTests: XCTestCase {
    func natural(_ text: String) -> String {
        NumberNormalizer.normalize(text, preset: .natural)
    }

    func testEmail() {
        XCTAssertEqual(natural("Write support@school.edu today."),
                       "Write support at school dot edu today.")
    }

    func testURLWithPath() {
        XCTAssertEqual(natural("Visit example.com/help now."),
                       "Visit example dot com slash help now.")
    }

    func testProtocolStripped() {
        XCTAssertEqual(natural("See https://www.kokoro.dev for docs."),
                       "See www dot kokoro dot dev for docs.")
    }

    func testAbbreviationsUntouched() {
        XCTAssertEqual(natural("This, e.g. that, in the U.S. today."),
                       "This, e.g. that, in the U.S. today.")
    }
}

final class PaddingTests: XCTestCase {
    func testPadAddsSilence() {
        let samples: [Float] = [0.5, 0.5]
        let padded = AudioProcessing.pad(samples, sampleRate: 1000,
                                         leadInMs: 100, leadOutMs: 50)
        XCTAssertEqual(padded.count, 100 + 2 + 50)
        XCTAssertEqual(padded.first, 0)
        XCTAssertEqual(padded.last, 0)
    }

    func testZeroPadIsIdentity() {
        let samples: [Float] = [0.1, 0.2]
        XCTAssertEqual(AudioProcessing.pad(samples, sampleRate: 24000,
                                           leadInMs: 0, leadOutMs: 0), samples)
    }
}
