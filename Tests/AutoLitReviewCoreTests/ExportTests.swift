import XCTest
@testable import AutoLitReviewCore

final class ExportTests: XCTestCase {
    private func sampleTests() throws -> (TempFolder, [TestRun]) {
        let ws = try TempFolder()
        try writeSingleTest(ws, "A-1", question: "What is \"good\", really?\nSecond line.", references: 2)
        try writeVariant(ws, "A-2", 1, question: "First <variant> & co", references: 3)
        try writeVariant(ws, "A-2", 2, references: 1, skip: ["dom"])
        try ws.write("A-2/notes.txt", "stray")
        return (ws, try WorkspaceScanner.scan(ws.url).tests)
    }

    func testCSVFieldQuoting() {
        XCTAssertEqual(Exporter.csvField("plain"), "plain")
        XCTAssertEqual(Exporter.csvField("a,b"), "\"a,b\"")
        XCTAssertEqual(Exporter.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(Exporter.csvField("two\nlines"), "\"two\nlines\"")
        XCTAssertEqual(Exporter.csvField("crlf\r\nline"), "\"crlf\r\nline\"")
        XCTAssertEqual(Exporter.csvField(""), "")
    }

    func testCSVRows() throws {
        let (ws, tests) = try sampleTests()
        _ = ws
        let csv = Exporter.csv(tests)
        XCTAssertTrue(csv.hasSuffix("\r\n"))
        let header = "Test ID,Type,Variant,Research Question,References Found,References in File Name,Count Matches,Status,Issues,Citation Key Clashes\r\n"
        XCTAssertTrue(csv.hasPrefix(header))
        XCTAssertTrue(csv.contains("A-1,Single RQ,,\"What is \"\"good\"\", really?\nSecond line.\",2,2,Yes,Complete,,\r\n"))
        XCTAssertTrue(csv.contains("A-2,Multiple RQs,1,First <variant> & co,3,3,Yes,Warnings,Warning: Unrecognised item: notes.txt,\r\n"))
        XCTAssertTrue(csv.contains("A-2,Multiple RQs,2,Question 2?,1,1,Yes,Errors,Warning: Unrecognised item: notes.txt; Error: Report (HTML DOM) is missing"))

        let data = Exporter.csvData(tests)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testHTMLIsSelfContainedAndEscaped() throws {
        let (ws, tests) = try sampleTests()
        _ = ws
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let html = Exporter.html(tests, workspaceName: "Q3 <runs>", generated: date,
                                 timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.contains("src="))
        XCTAssertTrue(html.contains("Q3 &lt;runs&gt;"))
        XCTAssertTrue(html.contains("exported 2026-09-21 14:13"))
        XCTAssertTrue(html.contains("First &lt;variant&gt; &amp; co"))
        XCTAssertTrue(html.contains("What is &quot;good&quot;, really?"))
        XCTAssertTrue(html.contains("2 tests: "))
        XCTAssertTrue(html.contains(">1 complete<"))
        XCTAssertTrue(html.contains(">0 with warnings<"))
        XCTAssertTrue(html.contains(">1 with errors<"))
        XCTAssertTrue(html.contains("3 research questions and 6 references found."))
        // A-2 has two rows plus its issues row.
        XCTAssertTrue(html.contains("<th scope=\"rowgroup\" class=\"id\" rowspan=\"3\">A-2</th>"))
        XCTAssertTrue(html.contains("<span class=\"sev\">Error</span> Variant 2: Report (HTML DOM) is missing"))
    }

    func testKeyClashesInBothExports() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "KC-2", 1)
        try writeVariant(ws, "KC-2", 2, skip: ["bib"])
        try ws.write("KC-2/KC-2_variant2_references_n4.bib",
                     "@article{Smith2025,}\n@article{Lee,}\n@article{Smith2025,}\n@article{lee,}\n")
        let tests = try WorkspaceScanner.scan(ws.url).tests
        XCTAssertEqual(tests[0].status, .complete)

        let csv = Exporter.csv(tests)
        XCTAssertTrue(csv.contains(",Complete,,Smith2025 (line 1) and Smith2025 (line 3); Lee (line 2) and lee (line 4)\r\n"))

        let html = Exporter.html(tests, workspaceName: "w", generated: Date())
        XCTAssertTrue(html.contains("<li class=\"info\"><span class=\"sev\">Key clash</span> Variant 2: Smith2025 (line 1) and Smith2025 (line 3)</li>"))
        XCTAssertTrue(html.contains("rowspan=\"3\">KC-2</th>"))
        XCTAssertFalse(html.contains("<span class=\"sev\">Warning</span>"))
    }

    func testHTMLMarksMismatchedCounts() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "M-1", references: 4, namedCount: 5)
        let tests = try WorkspaceScanner.scan(ws.url).tests
        let html = Exporter.html(tests, workspaceName: "w", generated: Date())
        XCTAssertTrue(html.contains("<td class=\"num mismatch\">5<span class=\"visually-hidden\"> (does not match)</span></td>"))
    }

    func testEmptyWorkspaceHTML() {
        let html = Exporter.html([], workspaceName: "Empty", generated: Date())
        XCTAssertTrue(html.contains("This workspace has no tests yet."))
        XCTAssertFalse(html.contains("<table>"))
    }

    func testGroupedNumbers() {
        XCTAssertEqual(Exporter.grouped(0), "0")
        XCTAssertEqual(Exporter.grouped(999), "999")
        XCTAssertEqual(Exporter.grouped(1000), "1,000")
        XCTAssertEqual(Exporter.grouped(1532), "1,532")
        XCTAssertEqual(Exporter.grouped(1234567), "1,234,567")
    }

    func testEscape() {
        XCTAssertEqual(Exporter.escape("a<b>&\"c'"), "a&lt;b&gt;&amp;&quot;c&#39;")
    }
}
