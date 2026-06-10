import XCTest
@testable import KokoroStudio

final class PronunciationDictionaryTests: XCTestCase {
    func testParseSkipsCommentsAndBlanks() {
        let rules = PronunciationDictionary.parse("""
        # phonetic respellings
        kokoro = koh koh roh

        SQL = sequel
        not a rule line
        """)
        XCTAssertEqual(rules, [
            PronunciationRule(word: "kokoro", replacement: "koh koh roh"),
            PronunciationRule(word: "SQL", replacement: "sequel"),
        ])
    }

    func testApplyIsCaseInsensitiveWholeWord() {
        let rules = [PronunciationRule(word: "SQL", replacement: "sequel")]
        let output = PronunciationDictionary.apply(
            rules, to: "Sql and SQL but not SQLite.")
        XCTAssertEqual(output, "sequel and sequel but not SQLite.")
    }

    func testApplyHandlesRegexSpecialCharacters() {
        let rules = [PronunciationRule(word: "C++", replacement: "see plus plus")]
        // "C++" has no trailing word boundary after '+'; rule should not crash
        // and should leave unrelated text alone.
        _ = PronunciationDictionary.apply(rules, to: "I write C++ daily.")
    }
}

final class ScriptSegmenterTests: XCTestCase {
    func testZeroPausesPassThrough() {
        let segments = ScriptSegmenter.segment("Hello, world.\nNew line.",
                                               paragraphPauseMs: 0,
                                               punctuationPauseMs: 0)
        XCTAssertEqual(segments,
                       [ScriptSegment(text: "Hello, world.\nNew line.", pauseAfterMs: 0)])
    }

    func testParagraphSplit() {
        let segments = ScriptSegmenter.segment("First paragraph.\n\nSecond paragraph.",
                                               paragraphPauseMs: 500,
                                               punctuationPauseMs: 0)
        XCTAssertEqual(segments, [
            ScriptSegment(text: "First paragraph.", pauseAfterMs: 500),
            ScriptSegment(text: "Second paragraph.", pauseAfterMs: 0),
        ])
    }

    func testPunctuationSplitKeepsDelimiters() {
        let segments = ScriptSegmenter.segment("Hello, world. Done",
                                               paragraphPauseMs: 0,
                                               punctuationPauseMs: 200)
        XCTAssertEqual(segments, [
            ScriptSegment(text: "Hello,", pauseAfterMs: 200),
            ScriptSegment(text: "world.", pauseAfterMs: 200),
            ScriptSegment(text: "Done", pauseAfterMs: 0),
        ])
    }

    func testEllipsisDoesNotCreateEmptySegments() {
        let segments = ScriptSegmenter.segment("Wait... what?",
                                               paragraphPauseMs: 0,
                                               punctuationPauseMs: 150)
        XCTAssertEqual(segments.map(\.text), ["Wait...", "what?"])
    }

    func testEmptyScript() {
        XCTAssertTrue(ScriptSegmenter.segment("  \n ", paragraphPauseMs: 500,
                                              punctuationPauseMs: 100).isEmpty)
    }
}
