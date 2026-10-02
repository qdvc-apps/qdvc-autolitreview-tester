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
        XCTAssertEqual(summary.duplicateKeys, ["smith2020", "Jones"])
        XCTAssertEqual(summary.entriesWithoutKey, 1)
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
