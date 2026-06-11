import XCTest
@testable import KokoroStudio

final class DocumentStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-store-tests-\(UUID().uuidString)")
        DocumentStore.directoryOverride = tempDir
    }

    override func tearDown() {
        DocumentStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveListLoadRoundTrip() throws {
        var meta = ScriptDocumentMeta(title: "Lesson 1")
        meta.profileName = "Course Voice"
        try DocumentStore.save(meta: meta, text: "Hello there.")
        let listed = DocumentStore.list()
        XCTAssertEqual(listed.map(\.id), [meta.id])
        XCTAssertEqual(listed.first?.title, "Lesson 1")
        XCTAssertEqual(listed.first?.profileName, "Course Voice")
        XCTAssertEqual(DocumentStore.loadText(id: meta.id), "Hello there.")
    }

    func testListSortsByUpdatedAtDescending() throws {
        var older = ScriptDocumentMeta(title: "Old")
        older.updatedAt = Date(timeIntervalSince1970: 100)
        var newer = ScriptDocumentMeta(title: "New")
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        try DocumentStore.save(meta: older, text: "a")
        try DocumentStore.save(meta: newer, text: "b")
        XCTAssertEqual(DocumentStore.list().map(\.title), ["New", "Old"])
    }

    func testDeleteRemovesBothFiles() throws {
        let meta = ScriptDocumentMeta(title: "Doomed")
        try DocumentStore.save(meta: meta, text: "bye")
        DocumentStore.delete(id: meta.id)
        XCTAssertTrue(DocumentStore.list().isEmpty)
        XCTAssertEqual(DocumentStore.loadText(id: meta.id), "")
    }

    func testDuplicateCopiesTextWithNewIdentity() throws {
        let meta = ScriptDocumentMeta(title: "Original")
        try DocumentStore.save(meta: meta, text: "content")
        let copy = try XCTUnwrap(DocumentStore.duplicate(id: meta.id))
        XCTAssertNotEqual(copy.id, meta.id)
        XCTAssertEqual(copy.title, "Original copy")
        XCTAssertEqual(DocumentStore.loadText(id: copy.id), "content")
        XCTAssertEqual(DocumentStore.list().count, 2)
    }

    func testAutoTitleFromFirstLine() {
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: "# Welcome Tour\nHi."),
                       "Welcome Tour")
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: "Plain first line here\nMore."),
                       "Plain first line here")
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: ""), "Untitled")
        let long = String(repeating: "x", count: 100)
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: long).count, 40)
    }
}
