import XCTest
@testable import KokoroStudio

final class AuditionSupportTests: XCTestCase {
    func testCacheKeyStableAndDistinct() {
        XCTAssertEqual(
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"),
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"))
        XCTAssertNotEqual(
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"),
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k2"))
        XCTAssertNotEqual(
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"),
            AuditionSupport.cacheKey(text: "Hi.", voiceLabel: "k3"))
    }

    func testDefaultTextIsFirstProseSentence() {
        XCTAssertEqual(AuditionSupport.defaultText(from: """
        # Heading line
        @Maya: First sentence here. Second sentence.
        """), "First sentence here.")
    }

    func testDefaultTextEmptyScript() {
        XCTAssertEqual(AuditionSupport.defaultText(from: "   \n"), "")
    }

    func testDefaultTextCapsLength() {
        let long = String(repeating: "word ", count: 100)
        XCTAssertLessThanOrEqual(
            AuditionSupport.defaultText(from: long).count, 240)
    }
}
