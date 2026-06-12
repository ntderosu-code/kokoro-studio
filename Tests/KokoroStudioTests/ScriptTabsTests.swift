import XCTest
@testable import KokoroStudio

final class ScriptTabsTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    func testOpenNewAppendsAndActivates() {
        let state = ScriptTabs.open(c, in: .init(openIDs: [a, b], activeID: a))
        XCTAssertEqual(state, .init(openIDs: [a, b, c], activeID: c))
    }

    func testOpenExistingJustActivates() {
        let state = ScriptTabs.open(b, in: .init(openIDs: [a, b], activeID: a))
        XCTAssertEqual(state, .init(openIDs: [a, b], activeID: b))
    }

    func testCloseInactiveKeepsActive() {
        let state = ScriptTabs.close(a, in: .init(openIDs: [a, b, c], activeID: b),
                                     library: [a, b, c])
        XCTAssertEqual(state, .init(openIDs: [b, c], activeID: b))
    }

    func testCloseActiveSelectsRightNeighborThenLeft() {
        let mid = ScriptTabs.close(b, in: .init(openIDs: [a, b, c], activeID: b),
                                   library: [a, b, c])
        XCTAssertEqual(mid, .init(openIDs: [a, c], activeID: c))
        let last = ScriptTabs.close(c, in: .init(openIDs: [a, c], activeID: c),
                                    library: [a, b, c])
        XCTAssertEqual(last, .init(openIDs: [a], activeID: a))
    }

    func testCloseLastTabFallsBackToMostRecentLibraryScript() {
        let state = ScriptTabs.close(a, in: .init(openIDs: [a], activeID: a),
                                     library: [d, a, b])
        XCTAssertEqual(state, .init(openIDs: [d], activeID: d))
    }

    func testCloseLastTabWithEmptyLibraryGoesEmpty() {
        let state = ScriptTabs.close(a, in: .init(openIDs: [a], activeID: a),
                                     library: [])
        XCTAssertEqual(state, .init(openIDs: [], activeID: nil))
    }

    func testCloseOthers() {
        let state = ScriptTabs.closeOthers(keeping: b,
                                           in: .init(openIDs: [a, b, c], activeID: a))
        XCTAssertEqual(state, .init(openIDs: [b], activeID: b))
    }

    func testReconcileDropsMissingAndFixesActive() {
        let state = ScriptTabs.reconcile(.init(openIDs: [a, b, c], activeID: c),
                                         library: [a, b, d])
        XCTAssertEqual(state, .init(openIDs: [a, b], activeID: a))
    }

    func testReconcileEmptyOpenSeedsFromLibrary() {
        let state = ScriptTabs.reconcile(.init(openIDs: [], activeID: nil),
                                         library: [d, a])
        XCTAssertEqual(state, .init(openIDs: [d], activeID: d))
    }
}
