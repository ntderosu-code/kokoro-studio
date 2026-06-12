import XCTest
@testable import KokoroStudio

final class CaptionWriterTests: XCTestCase {
    func testBuildCuesAccountsForPauses() {
        let cues = CaptionWriter.buildCues(segments: [
            ("First sentence.", 24000, 500, nil),   // 1s audio + 0.5s pause
            ("Second sentence.", 48000, 0, nil),    // 2s audio
        ], sampleRate: 24000)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[1].start, 1.5, accuracy: 0.001)
        XCTAssertEqual(cues[1].end, 3.5, accuracy: 0.001)
    }

    func testAdjustShiftsAndClamps() {
        let cues = [CaptionCue(start: 0.5, end: 2.0, text: "Hi"),
                    CaptionCue(start: 2.5, end: 4.0, text: "There")]
        let adjusted = CaptionWriter.adjust(cues, offset: 0.5, totalDuration: 3.2)
        XCTAssertEqual(adjusted[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(adjusted[0].end, 1.5, accuracy: 0.001)
        XCTAssertEqual(adjusted[1].end, 3.2, accuracy: 0.001) // clamped
    }

    func testVTTFormat() {
        let output = CaptionWriter.vtt([CaptionCue(start: 0, end: 1.5, text: "Hello.")])
        XCTAssertTrue(output.hasPrefix("WEBVTT\n"))
        XCTAssertTrue(output.contains("00:00:00.000 --> 00:00:01.500"))
        XCTAssertTrue(output.contains("Hello."))
    }

    func testSRTFormat() {
        let output = CaptionWriter.srt([
            CaptionCue(start: 0, end: 1.5, text: "Hello."),
            CaptionCue(start: 2, end: 3661.25, text: "Bye."),
        ])
        XCTAssertTrue(output.hasPrefix("1\n00:00:00,000 --> 00:00:01,500"))
        XCTAssertTrue(output.contains("2\n00:00:02,000 --> 01:01:01,250"))
    }

    func testBuildCuesCarriesSpeaker() {
        let cues = CaptionWriter.buildCues(segments: [
            ("Hi.", 24000, 0, "Alex"),
            ("Bye.", 24000, 0, nil),
        ], sampleRate: 24000)
        XCTAssertEqual(cues.map(\.speaker), ["Alex", nil])
    }

    func testAdjustPreservesSpeaker() {
        let cues = [CaptionCue(start: 0.5, end: 2.0, text: "Hi", speaker: "Alex")]
        let adjusted = CaptionWriter.adjust(cues, offset: 0.5, totalDuration: 3.0)
        XCTAssertEqual(adjusted[0].speaker, "Alex")
    }

    func testVTTLabelsSpeakerOnlyOnChange() {
        let output = CaptionWriter.vtt([
            CaptionCue(start: 0, end: 1, text: "Untagged intro."),
            CaptionCue(start: 1, end: 2, text: "Hello.", speaker: "Alex"),
            CaptionCue(start: 2, end: 3, text: "Still me.", speaker: "Alex"),
            CaptionCue(start: 3, end: 4, text: "Hi back.", speaker: "Sam"),
        ])
        XCTAssertTrue(output.contains("\nUntagged intro.\n"))
        XCTAssertTrue(output.contains("\nAlex: Hello.\n"))
        XCTAssertTrue(output.contains("\nStill me.\n"))
        XCTAssertFalse(output.contains("Alex: Still me."))
        XCTAssertTrue(output.contains("\nSam: Hi back.\n"))
        XCTAssertFalse(output.contains("@"))
    }

    func testSRTLabelsSpeakerOnlyOnChange() {
        let output = CaptionWriter.srt([
            CaptionCue(start: 0, end: 1, text: "Hello.", speaker: "Alex"),
            CaptionCue(start: 1, end: 2, text: "Still me.", speaker: "Alex"),
            CaptionCue(start: 2, end: 3, text: "Back to plain.", speaker: "Narrator"),
        ])
        XCTAssertTrue(output.contains("\nAlex: Hello.\n"))
        XCTAssertFalse(output.contains("Alex: Still me."))
        XCTAssertTrue(output.contains("\nNarrator: Back to plain.\n"))
        XCTAssertFalse(output.contains("@"))
    }

    func testSentenceSplitForCaptions() {
        let segments = ScriptSegmenter.segment(
            "One sentence. Another one! A third?",
            pauses: PauseSettings(paragraphMs: 0, sentenceMs: 0,
                                  clauseMs: 0, headingMs: 0),
            sentenceSplit: true)
        XCTAssertEqual(segments.map(\.text),
                       ["One sentence.", "Another one!", "A third?"])
        XCTAssertTrue(segments.allSatisfy { $0.pauseAfterMs == 0 })
    }
}
