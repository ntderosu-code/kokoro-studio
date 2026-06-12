import XCTest
@testable import KokoroStudio

final class ParagraphSpeakersTests: XCTestCase {
    func testUntaggedScriptIsAllNarrator() {
        let script = "First para.\n\nSecond para."
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans.map(\.speaker), ["Narrator", "Narrator"])
        XCTAssertEqual(spans.map(\.hasLiteralTag), [false, false])
    }

    func testInlineTagSetsSpeakerForItsParagraph() {
        let script = "@Alex: Hello there.\n\n@Sam: Hi back."
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.map(\.speaker), ["Alex", "Sam"])
        XCTAssertEqual(spans.map(\.hasLiteralTag), [true, true])
    }

    func testTagIsStickyAcrossUntaggedParagraphs() {
        let script = "@Alex:\nLine one.\n\nLine two still Alex.\n\n@Sam:\nNow Sam."
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.map(\.speaker), ["Alex", "Alex", "Sam"])
        XCTAssertEqual(spans.map(\.hasLiteralTag), [true, false, true])
    }

    func testBlankLinesProduceNoEmptySpans() {
        let script = "\n\n@Alex:\nHello.\n\n\n\nGoodbye.\n"
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.map(\.speaker), ["Alex", "Alex"])
    }

    func testSpanRangesCoverTheRightText() {
        let script = "@Alex:\nHello.\n\nGoodbye."
        let spans = ParagraphSpeakers.resolve(script: script)
        let ns = script as NSString
        XCTAssertTrue(ns.substring(with: spans[0].range).contains("@Alex:"))
        XCTAssertTrue(ns.substring(with: spans[1].range).contains("Goodbye."))
    }
}
