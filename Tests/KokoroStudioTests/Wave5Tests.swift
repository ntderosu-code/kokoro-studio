import XCTest
@testable import KokoroStudio

final class ScriptLinterTests: XCTestCase {
    func testFlagsUnknownAcronyms() {
        let rules = PronunciationDictionary.parse("CSWE = @letters")
        let suspects = ScriptLinter.acronymSuspects(
            in: "The CSWE and MSW programs follow APA style. OK?",
            coveredBy: rules)
        XCTAssertEqual(suspects, ["MSW", "APA"]) // CSWE covered, OK known-fine
    }

    func testNoFalsePositivesOnNormalText() {
        XCTAssertTrue(ScriptLinter.acronymSuspects(
            in: "Plain sentences only here. I am fine.", coveredBy: []).isEmpty)
    }
}

final class ModuleSplitterTests: XCTestCase {
    func testSplitsAtMarkers() {
        let modules = ModuleSplitter.split("""
        ## file: intro
        Welcome to the course.
        ## file: lesson-1
        First lesson body.
        More of it.
        """)
        XCTAssertEqual(modules, [
            ScriptModule(name: "intro", body: "Welcome to the course."),
            ScriptModule(name: "lesson-1", body: "First lesson body.\nMore of it."),
        ])
    }

    func testPreambleBecomesNumberedModule() {
        let modules = ModuleSplitter.split("Before any marker.\n## file: a\nBody.")
        XCTAssertEqual(modules.first?.name, "module-1")
        XCTAssertEqual(modules.count, 2)
    }

    func testNoMarkersSingleModule() {
        XCTAssertEqual(ModuleSplitter.split("Just text."),
                       [ScriptModule(name: "module-1", body: "Just text.")])
    }
}

final class EmphasisTests: XCTestCase {
    func testEmphasisSplitsWithBreathAndSpeed() {
        let segments = ScriptSegmenter.segment(
            "The *key term* matters here.",
            pauses: PauseSettings(paragraphMs: 0, sentenceMs: 0,
                                  clauseMs: 0, headingMs: 0))
        XCTAssertEqual(segments.map(\.text),
                       ["The", "key term", "matters here."])
        XCTAssertEqual(segments[0].pauseAfterMs, ScriptSegmenter.emphasisPauseMs)
        XCTAssertEqual(segments[1].pauseAfterMs, ScriptSegmenter.emphasisPauseMs)
        XCTAssertEqual(segments[1].speedMultiplier,
                       ScriptSegmenter.emphasisSpeedMultiplier)
        XCTAssertEqual(segments[2].speedMultiplier, 1)
    }

    func testNoEmphasisNoSplit() {
        let segments = ScriptSegmenter.segment(
            "Multiply 3 * 4 by hand.",
            pauses: PauseSettings(paragraphMs: 0, sentenceMs: 0,
                                  clauseMs: 0, headingMs: 0))
        // A lone * (spaced math) must not trigger emphasis splitting.
        XCTAssertEqual(segments.count, 1)
    }
}
