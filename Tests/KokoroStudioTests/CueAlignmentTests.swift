import XCTest
@testable import KokoroStudio

final class CueAlignmentTests: XCTestCase {
    func testExactTextAlignsEveryCue() {
        let script = "First sentence here. Second one follows. Third closes."
        let cues = ["First sentence here.", "Second one follows.", "Third closes."]
        let ranges = CueAlignment.align(cues: cues, script: script)
        XCTAssertEqual(ranges.count, 3)
        let ns = script as NSString
        XCTAssertEqual(ranges.compactMap { $0.map(ns.substring(with:)) }, cues)
    }

    func testRewrittenWordsStillAlignViaNeighbors() {
        // Dictionary turned "APA" into "A. P. A." in the cue; surrounding
        // words still anchor the sentence.
        let script = "Follow APA style closely. Then continue on."
        let cues = ["Follow A. P. A. style closely.", "Then continue on."]
        let ranges = CueAlignment.align(cues: cues, script: script)
        XCTAssertNotNil(ranges[0])
        XCTAssertNotNil(ranges[1])
        let ns = script as NSString
        XCTAssertTrue(ns.substring(with: ranges[0]!).hasPrefix("Follow"))
        XCTAssertEqual(ns.substring(with: ranges[1]!), "Then continue on.")
    }

    func testUnmatchableCueIsNilWithoutDerailingRest() {
        let script = "Alpha beta gamma. Delta epsilon zeta."
        let cues = ["completely unrelated words", "Delta epsilon zeta."]
        let ranges = CueAlignment.align(cues: cues, script: script)
        XCTAssertNil(ranges[0])
        XCTAssertNotNil(ranges[1])
    }

    func testCueIndexAtTime() {
        let cues = [CaptionCue(start: 0, end: 2, text: "a"),
                    CaptionCue(start: 2.5, end: 4, text: "b")]
        XCTAssertEqual(CueAlignment.cueIndex(at: 1.0, cues: cues), 0)
        XCTAssertEqual(CueAlignment.cueIndex(at: 3.0, cues: cues), 1)
        XCTAssertNil(CueAlignment.cueIndex(at: 2.2, cues: cues)) // in the pause
        XCTAssertNil(CueAlignment.cueIndex(at: 9.0, cues: cues))
    }
}
