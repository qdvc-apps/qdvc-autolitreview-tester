import XCTest
@testable import AutoLitReviewCore

final class ExportDateTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> ExportDate { ExportDate(year: y, month: m, day: d)! }

    func testParsesCommonForms() {
        XCTAssertEqual(ExportDate.parse("02 October 2026"), date(2026, 10, 2))
        XCTAssertEqual(ExportDate.parse("2 Oct 2026"), date(2026, 10, 2))
        XCTAssertEqual(ExportDate.parse("7 Sept 2026"), date(2026, 9, 7))
        XCTAssertEqual(ExportDate.parse("October 2, 2026"), date(2026, 10, 2))
        XCTAssertEqual(ExportDate.parse("2026-10-02"), date(2026, 10, 2))
        XCTAssertEqual(ExportDate.parse("02/10/2026"), date(2026, 10, 2))
        XCTAssertEqual(ExportDate.parse("02 October 2026 10:15 GMT"), date(2026, 10, 2))
        XCTAssertNil(ExportDate.parse("31 February 2026"))
        XCTAssertNil(ExportDate.parse("29 February 2025"))
        XCTAssertEqual(ExportDate.parse("29 February 2024"), date(2024, 2, 29))
        XCTAssertNil(ExportDate.parse("sometime soon"))
        XCTAssertNil(ExportDate.parse("02 October"))
    }

    func testFindsDatesAnywhereInTheFile() {
        let scopus = "Scopus\r\nEXPORT DATE: 02 October 2026\r\n\r\n@ARTICLE{a, title={A}}\n"
        XCTAssertEqual(ExportDate.find(in: scopus), [date(2026, 10, 2)])
        let mixed = """
        Export date 1 October 2026
        @article{a, note = {EXPORT DATE: 02 Oct 2026}}
        @article{b, note = {export date: 2 October 2026; other}}
        @article{c, note = "EXPORT DATE: nonsense"}
        """
        XCTAssertEqual(ExportDate.find(in: mixed), [date(2026, 10, 1), date(2026, 10, 2)])
        XCTAssertEqual(ExportDate.find(in: "@article{a, title={No date}}"), [])
        XCTAssertEqual(BibTeX.summary(of: scopus).exportDates, [date(2026, 10, 2)])
        XCTAssertEqual(BibTeX.summary(of: scopus).entries, 1)
    }

    func testFormatting() {
        XCTAssertEqual(date(2026, 10, 2).iso, "2026-10-02")
        XCTAssertEqual(date(2026, 10, 2).long, "2 October 2026")
        XCTAssertEqual(ExportDate.longRange([]), nil)
        XCTAssertEqual(ExportDate.longRange([date(2026, 10, 2)]), "2 October 2026")
        XCTAssertEqual(ExportDate.longRange([date(2026, 10, 2), date(2026, 10, 1)]), "1\u{2013}2 October 2026")
        XCTAssertEqual(ExportDate.longRange([date(2026, 9, 30), date(2026, 10, 2)]), "30 September \u{2013} 2 October 2026")
        XCTAssertEqual(ExportDate.longRange([date(2025, 12, 31), date(2026, 1, 2)]),
                       "31 December 2025 \u{2013} 2 January 2026")
        XCTAssertEqual(ExportDate.isoRange([date(2026, 10, 2), date(2026, 10, 1)]), "2026-10-01 to 2026-10-02")
        XCTAssertEqual(ExportDate.isoRange([date(2026, 10, 2)]), "2026-10-02")

        XCTAssertEqual(date(2026, 9, 23).short, "23 Sep 2026")
        XCTAssertEqual(ExportDate.shortRange([]), nil)
        XCTAssertEqual(ExportDate.shortRange([date(2026, 9, 23)]), "23 Sep 2026")
        XCTAssertEqual(ExportDate.shortRange([date(2026, 10, 1), date(2026, 10, 2)]), "1\u{2013}2 Oct 2026")
        XCTAssertEqual(ExportDate.shortRange([date(2026, 9, 30), date(2026, 10, 2)]), "30 Sep \u{2013} 2 Oct 2026")
        XCTAssertEqual(ExportDate.shortRange([date(2025, 12, 31), date(2026, 1, 2)]), "31 Dec 2025 \u{2013} 2 Jan 2026")
    }

    func testTestDateIsTheRangeOfItsVariants() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "R-1", 1, skip: ["bib"])
        try writeVariant(ws, "R-1", 2, skip: ["bib"])
        try writeVariant(ws, "R-1", 3, skip: ["bib"])
        try ws.write("R-1/R-1_variant1_references_n1.bib", "EXPORT DATE: 2 October 2026\n" + bibtex(1))
        try ws.write("R-1/R-1_variant2_references_n1.bib", "EXPORT DATE: 1 October 2026\n" + bibtex(1))
        try ws.write("R-1/R-1_variant3_references_n1.bib", bibtex(1))
        let test = try XCTUnwrap(try WorkspaceScanner.scan(ws.url).test("R-1"))
        XCTAssertEqual(test.questions.map(\.exportDates), [[date(2026, 10, 2)], [date(2026, 10, 1)], []])
        XCTAssertEqual(test.exportDates, [date(2026, 10, 1), date(2026, 10, 2)])
        XCTAssertEqual(test.dateText, "1\u{2013}2 October 2026")
        XCTAssertEqual(test.status, .complete, "a missing export date is not a problem")
    }
}
