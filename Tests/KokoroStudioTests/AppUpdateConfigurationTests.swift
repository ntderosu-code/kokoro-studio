import XCTest
@testable import KokoroStudio

final class AppUpdateConfigurationTests: XCTestCase {
    func testRequiresFeedURLAndPublicKey() {
        let configuration = AppUpdateConfiguration(infoDictionary: [:])

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertNil(configuration.feedURL)
        XCTAssertEqual(configuration.publicEDKey, "")
    }

    func testAcceptsHTTPSFeedURLAndPublicKey() {
        let configuration = AppUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": " abc123= \n",
        ])

        XCTAssertTrue(configuration.isConfigured)
        XCTAssertEqual(configuration.feedURL?.absoluteString,
                       "https://example.com/appcast.xml")
        XCTAssertEqual(configuration.publicEDKey, "abc123=")
    }

    func testRejectsNonHTTPSFeedURL() {
        let configuration = AppUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "http://example.com/appcast.xml",
            "SUPublicEDKey": "abc123=",
        ])

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertNil(configuration.feedURL)
    }

    func testRejectsBlankPublicKey() {
        let configuration = AppUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "  \n",
        ])

        XCTAssertFalse(configuration.isConfigured)
        XCTAssertEqual(configuration.publicEDKey, "")
    }
}
