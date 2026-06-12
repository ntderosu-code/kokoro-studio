import XCTest
@testable import KokoroStudio

final class SpeakerTagEditorTests: XCTestCase {
    private func apply(_ script: String, _ index: Int, _ speaker: String) -> String? {
        guard let edit = SpeakerTagEditor.assign(script: script,
                                                 paragraphIndex: index, to: speaker)
        else { return nil }
        let ns = script as NSString
        return ns.replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testInsertsTagWhenSpeakerDiffersFromInherited() {
        let script = "Hello there.\n\nGoodbye now."
        XCTAssertEqual(apply(script, 1, "Alex"),
                       "Hello there.\n\n@Alex:\nGoodbye now.")
    }

    func testNoOpWhenSpeakerMatchesInherited() {
        let script = "Hello there.\n\nGoodbye now."
        // Paragraph 0 inherits Narrator; choosing Narrator changes nothing.
        XCTAssertEqual(apply(script, 0, "Narrator"), script)
    }

    func testStripsRedundantBareTag() {
        // Both paragraphs are Alex; tagging para 1 as Alex (already inherited)
        // removes its now-redundant tag.
        let script = "@Alex:\nFirst.\n\n@Alex:\nSecond."
        XCTAssertEqual(apply(script, 1, "Alex"),
                       "@Alex:\nFirst.\n\nSecond.")
    }

    func testStripsRedundantInlineTagButKeepsText() {
        let script = "@Alex:\nFirst.\n\n@Alex: Second."
        XCTAssertEqual(apply(script, 1, "Alex"),
                       "@Alex:\nFirst.\n\nSecond.")
    }

    func testRenamesExistingTag() {
        let script = "@Alex:\nHello."
        XCTAssertEqual(apply(script, 0, "Sam"), "@Sam:\nHello.")
    }

    func testRenamesExistingInlineTagPreservingText() {
        let script = "@Alex: Hello there."
        XCTAssertEqual(apply(script, 0, "Sam"), "@Sam: Hello there.")
    }

    func testNarratorResetInsertsNarratorTag() {
        let script = "@Alex:\nHello.\n\nStill Alex here."
        XCTAssertEqual(apply(script, 1, "Narrator"),
                       "@Alex:\nHello.\n\n@Narrator:\nStill Alex here.")
    }

    func testOutOfRangeReturnsNil() {
        XCTAssertNil(SpeakerTagEditor.assign(script: "Hi.", paragraphIndex: 5, to: "Alex"))
    }
}
