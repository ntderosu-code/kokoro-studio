import XCTest
@testable import KokoroStudio

final class BatchSupportTests: XCTestCase {
    func testBatchFilename() {
        XCTAssertEqual(AppState.batchFilename(title: "Lesson 2: Intro/Review",
                                              moduleName: nil),
                       "Lesson 2- Intro-Review")
        XCTAssertEqual(AppState.batchFilename(title: "Course",
                                              moduleName: "lesson-2"),
                       "Course - lesson-2")
        XCTAssertEqual(AppState.batchFilename(title: "  ", moduleName: nil),
                       "kokoro")
    }
}
