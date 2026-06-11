import XCTest
@testable import KokoroStudio

final class ScriptImporterTests: XCTestCase {
    func testMarkdownHeadingsCollapseToScriptHeadings() {
        // All MD heading levels become single-# so they never collide with
        // the "## file:" module-split syntax.
        XCTAssertEqual(ScriptImporter.convertMarkdown("## Lesson One\nBody."),
                       "# Lesson One\nBody.")
        XCTAssertEqual(ScriptImporter.convertMarkdown("# Top\n### Deep"),
                       "# Top\n# Deep")
    }

    func testBoldBecomesEmphasisItalicBecomesPlain() {
        XCTAssertEqual(
            ScriptImporter.convertMarkdown("This **matters** but *this* less so."),
            "This *matters* but this less so.")
        XCTAssertEqual(
            ScriptImporter.convertMarkdown("Also __strong__ and _soft_."),
            "Also *strong* and soft.")
    }

    func testListsBlockquotesLinksImagesCode() {
        XCTAssertEqual(ScriptImporter.convertMarkdown("""
        - First point
        2. Second point
        > Quoted wisdom
        See [the docs](https://x.y) and ![diagram](img.png) here.
        Use `code` sparingly.
        """), """
        First point
        Second point
        Quoted wisdom
        See the docs and  here.
        Use code sparingly.
        """)
    }

    func testTablesAndRulesDropped() {
        XCTAssertEqual(ScriptImporter.convertMarkdown("""
        Before.
        | a | b |
        |---|---|
        | 1 | 2 |
        ---
        After.
        """), "Before.\nAfter.")
    }

    func testCodeFenceMarkersDroppedContentKept() {
        XCTAssertEqual(ScriptImporter.convertMarkdown("```\nplain inside\n```"),
                       "plain inside")
    }

    func testSmartPunctuationNormalized() {
        XCTAssertEqual(
            ScriptImporter.normalizePlainText("\u{201C}Hi\u{201D} it\u{2019}s\u{00A0}me\u{2026}"),
            "\"Hi\" it's me...")
    }
}
