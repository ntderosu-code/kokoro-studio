import XCTest
@testable import KokoroStudio

final class ScriptPatcherTests: XCTestCase {
    // MARK: changedLineRange

    func testDiffMiddleChange() {
        let old = ["a", "b", "c", "d"]
        let new = ["a", "X", "c", "d"]
        let diff = ScriptPatcher.changedLineRange(old: old, new: new)
        XCTAssertEqual(diff?.old, 1..<2)
        XCTAssertEqual(diff?.new, 1..<2)
    }

    func testDiffInsertion() {
        let diff = ScriptPatcher.changedLineRange(old: ["a", "b"],
                                                  new: ["a", "NEW", "b"])
        XCTAssertEqual(diff?.old, 1..<1)
        XCTAssertEqual(diff?.new, 1..<2)
    }

    func testDiffDeletion() {
        let diff = ScriptPatcher.changedLineRange(old: ["a", "b", "c"],
                                                  new: ["a", "c"])
        XCTAssertEqual(diff?.old, 1..<2)
        XCTAssertEqual(diff?.new, 1..<1)
    }

    func testDiffIdenticalIsNil() {
        XCTAssertNil(ScriptPatcher.changedLineRange(old: ["a"], new: ["a"]))
    }

    func testDiffChangeAtEnds() {
        XCTAssertEqual(ScriptPatcher.changedLineRange(
            old: ["a", "b"], new: ["X", "b"])?.old, 0..<1)
        XCTAssertEqual(ScriptPatcher.changedLineRange(
            old: ["a", "b"], new: ["a", "X"])?.old, 1..<2)
    }

    // MARK: plan

    /// 3 sentences, one per line, 1s of audio each at 1000 Hz "sample
    /// rate" with cues exactly on the second marks.
    private let oldScript = "First line here.\nSecond line here.\nThird line here."
    private let cues = [CaptionCue(start: 0.0, end: 0.9, text: "First line here."),
                        CaptionCue(start: 1.0, end: 1.9, text: "Second line here."),
                        CaptionCue(start: 2.0, end: 2.9, text: "Third line here.")]

    func testPlanMiddleLineEdit() {
        let plan = ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "First line here.\nA changed middle line.\nThird line here.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.replacementText, "A changed middle line.")
        XCTAssertEqual(plan?.replacedCueRange, 1..<2)
        // Cut from the start of cue 1 to the start of cue 2 (the old
        // trailing pause is cut too and re-appended fresh).
        XCTAssertEqual(plan?.cutSampleRange, 1000..<2000)
        XCTAssertEqual(plan?.trailingPauseMs, PauseSettings().paragraphMs)
    }

    func testPlanEditAtEndHasNoTrailingPause() {
        let plan = ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "First line here.\nSecond line here.\nA new ending.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.cutSampleRange, 2000..<2900)
        XCTAssertEqual(plan?.trailingPauseMs, 0)
    }

    func testPlanHeadingReplacementUsesHeadingPause() {
        let plan = ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "First line here.\n# Section Two\nThird line here.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.trailingPauseMs, PauseSettings().headingMs)
    }

    func testPlanPrependsSpeakerContext() {
        let old = "@Maya: Hello there.\nNice to meet you.\nGoodbye now."
        let speakerCues = [CaptionCue(start: 0, end: 0.9, text: "Hello there."),
                           CaptionCue(start: 1, end: 1.9, text: "Nice to meet you."),
                           CaptionCue(start: 2, end: 2.9, text: "Goodbye now.")]
        let plan = ScriptPatcher.plan(
            oldScript: old,
            newScript: "@Maya: Hello there.\nGreat to meet you.\nGoodbye now.",
            cues: speakerCues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.replacementText, "@Maya:\nGreat to meet you.")
    }

    func testPlanRejectsWholesaleRewrite() {
        XCTAssertNil(ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "Totally.\nDifferent.\nScript.\nNow longer.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings()))
    }

    func testPlanIdenticalIsNil() {
        XCTAssertNil(ScriptPatcher.plan(
            oldScript: oldScript, newScript: oldScript,
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings()))
    }

    // MARK: splice / rebuildCues

    func testSplice() {
        XCTAssertEqual(ScriptPatcher.splice(old: [1, 2, 3, 4, 5], cut: 1..<3,
                                            replacement: [9, 9, 9]),
                       [1, 9, 9, 9, 4, 5])
    }

    func testRebuildCuesShiftsTail() {
        let old = [CaptionCue(start: 0, end: 1, text: "a"),
                   CaptionCue(start: 2, end: 3, text: "b"),
                   CaptionCue(start: 4, end: 5, text: "c")]
        let rebuilt = ScriptPatcher.rebuildCues(
            old: old, replacedRange: 1..<2,
            newCues: [CaptionCue(start: 0, end: 1.5, text: "B long")],
            insertAt: 2, timeDelta: 0.5, totalDuration: 6)
        XCTAssertEqual(rebuilt, [CaptionCue(start: 0, end: 1, text: "a"),
                                 CaptionCue(start: 2, end: 3.5, text: "B long"),
                                 CaptionCue(start: 4.5, end: 5.5, text: "c")])
    }
}
