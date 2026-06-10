import XCTest
@testable import KokoroStudio

final class VoiceCatalogTests: XCTestCase {
    func testCatalogHas53Voices() {
        XCTAssertEqual(VoiceCatalog.all.count, 53)
    }

    func testIDsAreUniqueAndSequential() {
        XCTAssertEqual(VoiceCatalog.all.map(\.id), Array(0...52))
    }

    func testKnownVoices() {
        XCTAssertEqual(VoiceCatalog.all[3].name, "af_heart")
        XCTAssertEqual(VoiceCatalog.all[26].name, "bm_george")
        XCTAssertEqual(VoiceCatalog.all[52].name, "zm_yunyang")
    }

    func testEnglishGroupFirst() {
        XCTAssertEqual(VoiceCatalog.grouped.first?.label, "English (US female)")
        XCTAssertEqual(VoiceCatalog.grouped.map { $0.voices.count }.reduce(0, +), 53)
    }

    func testVoiceForUnknownIDFallsBack() {
        XCTAssertEqual(VoiceCatalog.voice(forID: 999).name, "af_heart")
    }

    func testRecommendedVoices() {
        let recommended = VoiceCatalog.all.filter(\.recommended).map(\.name)
        XCTAssertEqual(recommended, ["af_bella", "af_heart", "bm_george"])
    }

    func testDisplayNameFormatting() {
        XCTAssertEqual(VoiceCatalog.all[3].displayName, "★ Heart — warm, expressive")
        XCTAssertEqual(VoiceCatalog.all[13].displayName, "Eric — plain, conversational")
        XCTAssertEqual(VoiceCatalog.all[30].displayName, "Siwis (French)")
        XCTAssertEqual(VoiceCatalog.all[28].displayName, "Dora (Spanish)")
    }
}
