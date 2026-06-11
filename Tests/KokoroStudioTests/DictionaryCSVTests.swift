import XCTest
@testable import KokoroStudio

final class DictionaryCSVTests: XCTestCase {
    func testExportFormats() {
        let csv = DictionaryCSV.export(rulesText: """
        kokoro = koh koh roh
        APA = @letters
        NASA = @word
        IEP = @letters-first
        """)
        XCTAssertEqual(csv, """
        term,replacement,mode
        kokoro,koh koh roh,replace
        APA,,letters
        NASA,,word
        IEP,,letters-first

        """)
    }

    func testQuotingFieldsWithCommas() {
        let csv = DictionaryCSV.export(rulesText: "Smith, Jr. = smith junior")
        XCTAssertTrue(csv.contains("\"Smith, Jr.\",smith junior,replace"))
    }

    func testRoundTrip() {
        let original = """
        kokoro = koh koh roh
        APA = @letters
        NASA = @word
        IEP = @letters-first
        """
        let rules = DictionaryCSV.parse(DictionaryCSV.export(rulesText: original))
        XCTAssertEqual(rules, PronunciationDictionary.parse(original))
    }

    func testParseSkipsHeaderAndJunk() {
        let rules = DictionaryCSV.parse("""
        term,replacement,mode
        ,
        APA,,letters
        bogus,,unknown-mode
        """)
        XCTAssertEqual(rules, [PronunciationRule(word: "APA", kind: .letters)])
    }

    func testParseQuotedField() {
        let rules = DictionaryCSV.parse("\"Smith, Jr.\",smith junior,replace")
        XCTAssertEqual(rules, [PronunciationRule(word: "Smith, Jr.",
                                                 kind: .replace("smith junior"))])
    }

    func testMergeAppendsNewTerms() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "CSWE", kind: .letters)],
            into: "# my rules\nAPA = @letters\n", preferImported: false)
        XCTAssertEqual(result.mergedText,
                       "# my rules\nAPA = @letters\nCSWE = @letters\n")
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertTrue(result.conflictTerms.isEmpty)
    }

    func testMergeConflictKeepExisting() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "APA", kind: .word)],
            into: "APA = @letters\n", preferImported: false)
        XCTAssertEqual(result.mergedText, "APA = @letters\n")
        XCTAssertEqual(result.conflictTerms, ["APA"])
    }

    func testMergeConflictUseImported() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "APA", kind: .word)],
            into: "APA = @letters\n", preferImported: true)
        XCTAssertEqual(result.mergedText, "APA = @word\n")
    }

    func testMergeIdenticalRuleIsNeitherConflictNorAdd() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "APA", kind: .letters)],
            into: "APA = @letters\n", preferImported: false)
        XCTAssertEqual(result.mergedText, "APA = @letters\n")
        XCTAssertTrue(result.conflictTerms.isEmpty)
        XCTAssertEqual(result.addedCount, 0)
    }
}
