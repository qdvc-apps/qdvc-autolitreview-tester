import XCTest
@testable import AutoLitReviewCore

final class BibTeXTests: XCTestCase {
    func testCountsEntries() {
        XCTAssertEqual(BibTeX.summary(of: bibtex(5)).entries, 5)
        XCTAssertEqual(BibTeX.summary(of: "").entries, 0)
        XCTAssertEqual(BibTeX.summary(of: "% just a comment\n").entries, 0)
    }

    func testSkipsStringPreambleAndComment() {
        let text = """
        @string{ieee = "IEEE"}
        @PREAMBLE{"\\newcommand{\\noop}[1]{}"}
        @comment{This @article{fake, title={no}} is commented out}
        @Article{real1, title = {One}}
        @inproceedings{real2, title = {Two}, booktitle = ieee}
        """
        let summary = BibTeX.summary(of: text)
        XCTAssertEqual(summary.entries, 2)
        XCTAssertFalse(summary.endsInsideEntry)
    }

    func testParenthesisedEntriesAndNestedBraces() {
        let text = """
        @book(key1, title = {A {Nested {Deep}} Title (2nd edition)}, note = "plain")
        @misc{key2, title = {Has @misc{inside} text}, howpublished = {\\url{https://x.org/a@b}}}
        """
        let summary = BibTeX.summary(of: text)
        XCTAssertEqual(summary.entries, 2)
        XCTAssertFalse(summary.endsInsideEntry)
    }

    func testAtSignsOutsideEntriesAreNotEntries() {
        let text = """
        Contact me at someone@example.org or @ the desk.
        @article{a1, author = {x@y.z}}
        @ article {a2, title={spaced}}
        """
        XCTAssertEqual(BibTeX.summary(of: text).entries, 2)
    }

    func testDuplicateAndMissingKeys() {
        let text = """
        @article{Smith2020, title={A}}
        @article{smith2020, title={B}}
        @article{SMITH2020, title={C}}
        @article{Jones, title={D}}
        @article{Jones, title={E}}
        @article{, title={F}}
        """
        let summary = BibTeX.summary(of: text)
        XCTAssertEqual(summary.entries, 6)
        XCTAssertEqual(summary.keyClashes.map(\.description), [
            "Smith2020 (line 1), smith2020 (line 2) and SMITH2020 (line 3)",
            "Jones (line 4) and Jones (line 5)",
        ])
        XCTAssertEqual(summary.keyClashes.map(\.key), ["Smith2020", "Jones"])
        XCTAssertEqual(summary.entriesWithoutKey, 1)
    }

    func testSpacesInsideKeysAreTolerated() {
        let text = """
        @article{Smith 2020, title={A}}
        @article{ smith 2020 , title={B}}
        @book(Jones et al 2019, title = {C})
        @misc{Lee  2021
          , title={D}}
        @article{Smith2020, title={E}}
        @article{   , title={F}}
        """
        let summary = BibTeX.summary(of: text)
        XCTAssertEqual(summary.entries, 6)
        // Leading and trailing spaces are dropped, so the second key repeats the first.
        XCTAssertEqual(summary.keyClashes.map(\.description), ["Smith 2020 (line 1) and smith 2020 (line 2)"])
        XCTAssertEqual(summary.entriesWithoutKey, 1)
        XCTAssertFalse(summary.endsInsideEntry)
    }

    func testKeyClashLineNumbers() {
        // Blank lines, a multi-line entry, CRLF endings and an @ inside a field.
        let text = "% header\n\n@article{Smith2025,\n  title={A},\n  note={mail x@y.z}\n}\n\n"
            + "@article{Jones, title={B}}\r\n@article{Smith2025, title={C}}\r\n"
            + "@string{s = {x}}\n@article{Jones,\n title={D}}\n"
        let summary = BibTeX.summary(of: text)
        XCTAssertEqual(summary.entries, 4)
        XCTAssertEqual(summary.keyClashes, [
            KeyClash(occurrences: [KeyOccurrence(key: "Smith2025", line: 3), KeyOccurrence(key: "Smith2025", line: 9)]),
            KeyClash(occurrences: [KeyOccurrence(key: "Jones", line: 8), KeyOccurrence(key: "Jones", line: 11)]),
        ])
        XCTAssertEqual(summary.keyClashes[0].description, "Smith2025 (line 3) and Smith2025 (line 9)")
        XCTAssertTrue(BibTeX.summary(of: bibtex(5)).keyClashes.isEmpty)
    }

    func testUnbalancedEnd() {
        let summary = BibTeX.summary(of: "@article{a, title={ok}}\n@article{b, title={never closed}\n")
        XCTAssertEqual(summary.entries, 2)
        XCTAssertTrue(summary.endsInsideEntry)
    }

    func testReadsLatin1AndBOM() throws {
        let folder = try TempFolder()
        let latin = folder.url.appendingPathComponent("latin.bib")
        try Data("@article{m\u{FC}ller, title={\u{C4}}}\n".data(using: .isoLatin1)!).write(to: latin)
        XCTAssertEqual(try BibTeX.summary(contentsOf: latin).entries, 1)

        let bom = try folder.write("bom.md", "\u{FEFF}Question?")
        XCTAssertEqual(try TextSupport.readText(bom), "Question?")
    }
}
