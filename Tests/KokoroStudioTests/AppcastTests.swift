import Foundation
import XCTest

final class AppcastTests: XCTestCase {
    func testPagesAppcastIsValidRSS() throws {
        let appcastURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/appcast.xml")
        let data = try Data(contentsOf: appcastURL)
        let document = try XMLDocument(data: data)
        let rss = try XCTUnwrap(document.rootElement())
        let channel = try XCTUnwrap(rss.elements(forName: "channel").first)

        XCTAssertEqual(rss.name, "rss")
        XCTAssertEqual(rss.attribute(forName: "version")?.stringValue, "2.0")
        XCTAssertEqual(channel.elements(forName: "title").first?.stringValue,
                       "Kokoro Studio Updates")
        XCTAssertEqual(channel.elements(forName: "link").first?.stringValue,
                       "https://github.com/ntderosu-code/kokoro-studio/releases")
    }
}
