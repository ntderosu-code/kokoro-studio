import XCTest
@testable import KokoroStudio

final class DurationEstimatorTests: XCTestCase {
    let noPauses = PauseSettings(paragraphMs: 0, sentenceMs: 0, clauseMs: 0,
                                 headingMs: 0)

    func testSpeechTimeScalesWithWords() {
        let ten = Array(repeating: "word", count: 10).joined(separator: " ")
        let estimate = DurationEstimator.estimate(script: ten, pauses: noPauses,
                                                  wordsPerSecond: 2.0, speed: 1.0)
        XCTAssertEqual(estimate, 5.0, accuracy: 0.01)
    }

    func testSpeedHalvesDuration() {
        let ten = Array(repeating: "word", count: 10).joined(separator: " ")
        let estimate = DurationEstimator.estimate(script: ten, pauses: noPauses,
                                                  wordsPerSecond: 2.0, speed: 2.0)
        XCTAssertEqual(estimate, 2.5, accuracy: 0.01)
    }

    func testPausesAddExactly() {
        let pauses = PauseSettings(paragraphMs: 1000, sentenceMs: 0,
                                   clauseMs: 0, headingMs: 0)
        let estimate = DurationEstimator.estimate(
            script: "First line here\nSecond line here", pauses: pauses,
            wordsPerSecond: 3.0, speed: 1.0)
        XCTAssertEqual(estimate, 6.0 / 3.0 + 1.0, accuracy: 0.01)
    }

    func testEmptyScriptIsZero() {
        XCTAssertEqual(DurationEstimator.estimate(script: " ", pauses: noPauses,
                                                  wordsPerSecond: 2.8, speed: 1.0), 0)
    }

    func testCalibrationSmoothing() {
        let updated = DurationEstimator.calibrate(previousRate: 2.0, words: 30,
                                                  audioSeconds: 11.0,
                                                  pauseSeconds: 1.0, speed: 1.0)
        XCTAssertEqual(updated!, (2.0 + 3.0) / 2, accuracy: 0.01)
    }

    func testCalibrationRejectsJunk() {
        XCTAssertNil(DurationEstimator.calibrate(previousRate: 2.8, words: 2,
                                                 audioSeconds: 1.5,
                                                 pauseSeconds: 0, speed: 1.0))
        XCTAssertNil(DurationEstimator.calibrate(previousRate: 2.8, words: 100,
                                                 audioSeconds: 2.0,
                                                 pauseSeconds: 0, speed: 1.0))
    }

    func testFormatting() {
        XCTAssertEqual(DurationEstimator.formatted(45), "~0:45")
        XCTAssertEqual(DurationEstimator.formatted(200), "~3:20")
        XCTAssertEqual(DurationEstimator.formatted(3730), "~1:02:10")
    }
}
