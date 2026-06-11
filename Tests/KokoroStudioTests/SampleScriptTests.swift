import XCTest
@testable import KokoroStudio

final class SampleScriptTests: XCTestCase {
    func testSampleExercisesEverySyntaxFeature() {
        let text = SampleScript.text
        XCTAssertTrue(text.contains("[pause:"), "inline pause marker")
        XCTAssertTrue(text.contains("{Roush|rowsh}"), "inline override")
        XCTAssertEqual(ScriptSegmenter.speakerNames(in: text), ["Maya", "Sam"],
                       "dialogue speakers")
        XCTAssertEqual(ModuleSplitter.split(text).count, 2, "module marker")
        let segments = ScriptSegmenter.segment(text, pauses: PauseSettings())
        XCTAssertTrue(segments.contains {
            $0.speedMultiplier == ScriptSegmenter.emphasisSpeedMultiplier
        }, "emphasis span")
        XCTAssertFalse(ScriptLinter.acronymSuspects(in: text, coveredBy: [])
            .isEmpty, "acronyms that trigger the linter")
    }

    func testSeedGuard() {
        XCTAssertTrue(AppState.shouldSeedSample(hasSeeded: false, script: ""))
        XCTAssertTrue(AppState.shouldSeedSample(hasSeeded: false, script: " \n"))
        XCTAssertFalse(AppState.shouldSeedSample(hasSeeded: true, script: ""))
        XCTAssertFalse(AppState.shouldSeedSample(hasSeeded: false,
                                                 script: "My own script"))
    }
}
