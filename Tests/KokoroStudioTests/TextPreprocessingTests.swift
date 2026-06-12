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
            PronunciationRule(word: "kokoro", kind: .replace("koh koh roh")),
            PronunciationRule(word: "SQL", kind: .replace("sequel")),
        ])
    }

    func testParseModes() {
        let rules = PronunciationDictionary.parse("""
        APA = @letters
        NASA = @word
        IEP = @letters-first
        """)
        XCTAssertEqual(rules, [
            PronunciationRule(word: "APA", kind: .letters),
            PronunciationRule(word: "NASA", kind: .word),
            PronunciationRule(word: "IEP", kind: .lettersFirst),
        ])
    }

    func testApplyIsCaseInsensitiveWholeWord() {
        let rules = [PronunciationRule(word: "SQL", kind: .replace("sequel"))]
        let output = PronunciationDictionary.apply(
            rules, to: "Sql and SQL but not SQLite.")
        XCTAssertEqual(output, "sequel and sequel but not SQLite.")
    }

    func testSpelledOut() {
        XCTAssertEqual(PronunciationDictionary.spelledOut("APA"), "A. P. A.")
        XCTAssertEqual(PronunciationDictionary.spelledOut("MP3"), "M. P. 3")
    }

    func testLettersMode() {
        let rules = [PronunciationRule(word: "APA", kind: .letters)]
        XCTAssertEqual(PronunciationDictionary.apply(rules, to: "Use APA style."),
                       "Use A. P. A. style.")
    }

    func testWordModeIsNoop() {
        let rules = [PronunciationRule(word: "NASA", kind: .word)]
        XCTAssertEqual(PronunciationDictionary.apply(rules, to: "NASA launched."),
                       "NASA launched.")
    }

    func testLettersFirstOnlyFirstOccurrence() {
        let rules = [PronunciationRule(word: "IEP", kind: .lettersFirst)]
        let output = PronunciationDictionary.apply(
            rules, to: "An IEP is a plan. The IEP is reviewed yearly.")
        XCTAssertEqual(output,
                       "An I. E. P. is a plan. The IEP is reviewed yearly.")
    }

    func testApplyHandlesRegexSpecialCharacters() {
        let rules = [PronunciationRule(word: "C++", kind: .replace("see plus plus"))]
        // "C++" has no trailing word boundary after '+'; rule should not crash
        // and should leave unrelated text alone.
        _ = PronunciationDictionary.apply(rules, to: "I write C++ daily.")
    }
}

final class ScriptSegmenterTests: XCTestCase {
    func pauses(paragraph: Int = 0, sentence: Int = 0, clause: Int = 0,
                heading: Int = 0) -> PauseSettings {
        PauseSettings(paragraphMs: paragraph, sentenceMs: sentence,
                      clauseMs: clause, headingMs: heading)
    }

    func testZeroPausesPassThrough() {
        let segments = ScriptSegmenter.segment("Hello, world.\nNew line.",
                                               pauses: pauses())
        XCTAssertEqual(segments,
                       [ScriptSegment(text: "Hello, world.\nNew line.", pauseAfterMs: 0)])
    }

    func testParagraphSplit() {
        let segments = ScriptSegmenter.segment("First paragraph.\n\nSecond paragraph.",
                                               pauses: pauses(paragraph: 500))
        XCTAssertEqual(segments, [
            ScriptSegment(text: "First paragraph.", pauseAfterMs: 500),
            ScriptSegment(text: "Second paragraph.", pauseAfterMs: 0),
        ])
    }

    func testSentenceAndClausePausesDiffer() {
        let segments = ScriptSegmenter.segment("Hello, world. Done",
                                               pauses: pauses(sentence: 300, clause: 100))
        XCTAssertEqual(segments, [
            ScriptSegment(text: "Hello,", pauseAfterMs: 100),
            ScriptSegment(text: "world.", pauseAfterMs: 300),
            ScriptSegment(text: "Done", pauseAfterMs: 0),
        ])
    }

    func testSentencePauseOnlyDoesNotSplitClauses() {
        let segments = ScriptSegmenter.segment("Hello, world. Done",
                                               pauses: pauses(sentence: 300))
        XCTAssertEqual(segments.map(\.text), ["Hello, world.", "Done"])
    }

    func testInlinePauseMarker() {
        let segments = ScriptSegmenter.segment("Key term[pause:800] explained here.",
                                               pauses: pauses(paragraph: 500))
        XCTAssertEqual(segments, [
            ScriptSegment(text: "Key term", pauseAfterMs: 800),
            ScriptSegment(text: "explained here.", pauseAfterMs: 0),
        ])
    }

    func testInlinePauseMarkerDefaultDuration() {
        let segments = ScriptSegmenter.segment("Wait[pause] go.",
                                               pauses: pauses())
        XCTAssertEqual(segments.first?.pauseAfterMs,
                       PauseSettings.defaultInlineMarkerMs)
    }

    func testHeadingGetsHeadingPause() {
        let segments = ScriptSegmenter.segment("# Section One\nBody text.",
                                               pauses: pauses(paragraph: 400, heading: 1000))
        XCTAssertEqual(segments, [
            ScriptSegment(text: "Section One", pauseAfterMs: 1000),
            ScriptSegment(text: "Body text.", pauseAfterMs: 0),
        ])
    }

    func testSpeakerTags() {
        let script = """
        @Maya: Welcome to the clinic.
        @Sam: Thanks!
        Narration continues here.
        """
        let segments = ScriptSegmenter.segment(script, pauses: pauses(paragraph: 300))
        XCTAssertEqual(segments.map(\.speaker), ["Maya", "Sam", "Sam"])
        // NOTE: untagged lines inherit the previous speaker by design — a
        // speaker keeps talking until another tag appears.
        XCTAssertEqual(segments.map(\.text),
                       ["Welcome to the clinic.", "Thanks!", "Narration continues here."])
    }

    func testSpeakerNamesDetection() {
        XCTAssertEqual(ScriptSegmenter.speakerNames(
            in: "@Maya: hi\n@Sam: yo\n@Maya: again"), ["Maya", "Sam"])
    }

    func testEllipsisDoesNotCreateEmptySegments() {
        let segments = ScriptSegmenter.segment("Wait... what?",
                                               pauses: pauses(sentence: 150))
        XCTAssertEqual(segments.map(\.text), ["Wait...", "what?"])
    }

    func testEmptyScript() {
        XCTAssertTrue(ScriptSegmenter.segment("  \n ",
                                              pauses: pauses(paragraph: 500)).isEmpty)
    }
}

final class ProfileStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let name = "test-profile-\(UUID().uuidString)"
        defer { ProfileStore.delete(name: name) }
        let profile = Profile(engineKind: "kokoro", voiceID: 7,
                              speed: 1.2,
                              paragraphPauseMs: 450, sentencePauseMs: 200,
                              clausePauseMs: 50, headingPauseMs: 900,
                              pronunciationRules: "APA = @letters",
                              captionFormat: "vtt", normalizeLoudness: true,
                              exportFormat: "m4a", speakerVoicesJSON: "{\"Maya\":2}",
                              supertonicVoiceID: 6)
        try ProfileStore.save(profile, name: name)
        XCTAssertTrue(ProfileStore.list().contains(name))
        XCTAssertEqual(ProfileStore.load(name: name), profile)
    }
}
