import XCTest
@testable import KokoroStudio

final class VoiceVisibilityTests: XCTestCase {
    func testFavoritesPinFirstAndLeaveHomeGroup() {
        let groups = VoiceCatalog.visibleGroups(favorites: [3, 26], hidden: [],
                                                selectedID: 3)
        XCTAssertEqual(groups.first?.label, "Favorites")
        XCTAssertEqual(groups.first?.voices.map(\.id), [3, 26])
        // af_heart no longer duplicated in its home group (unique picker tags)
        let usFemale = groups.first { $0.label == "English (US female)" }
        XCTAssertFalse(usFemale!.voices.contains { $0.id == 3 })
    }

    func testHiddenVoicesDisappearExceptSelected() {
        let groups = VoiceCatalog.visibleGroups(favorites: [], hidden: [2, 3],
                                                selectedID: 3)
        let usFemale = groups.first { $0.label == "English (US female)" }!
        XCTAssertFalse(usFemale.voices.contains { $0.id == 2 }) // hidden
        XCTAssertTrue(usFemale.voices.contains { $0.id == 3 })  // selected survives
    }

    func testNoFavoritesNoFavoritesSection() {
        let groups = VoiceCatalog.visibleGroups(favorites: [], hidden: [],
                                                selectedID: 0)
        XCTAssertNotEqual(groups.first?.label, "Favorites")
        XCTAssertEqual(groups.flatMap(\.voices).count, 53)
    }

    func testFilenameWithoutTimestamp() {
        XCTAssertEqual(AudioExporter.defaultFilename(for: "Hello world today",
                                                     includeTimestamp: false),
                       "Hello-world-today")
        XCTAssertEqual(AudioExporter.defaultFilename(for: " ",
                                                     includeTimestamp: false),
                       "kokoro")
    }
}
