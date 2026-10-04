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
        let header = "Test ID,Type,Variant,Research Question,References Found,References in File Name,Count Matches,Status,Issues,Citation Key Clashes,Annotation,Ground Truth (APA 7),Ground Truth DOI,Export Date\r\n"
        XCTAssertTrue(csv.hasPrefix(header))
        XCTAssertTrue(csv.contains("A-1,Single RQ,,\"What is \"\"good\"\", really?\nSecond line.\",2,2,Yes,Complete,,,,,,\r\n"))
        XCTAssertTrue(csv.contains("A-2,Multiple RQs,1,First <variant> & co,3,3,Yes,Warnings,Warning: Unrecognised item: notes.txt,,,,,\r\n"))
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
        XCTAssertTrue(csv.contains(",Complete,,Smith2025 (line 1) and Smith2025 (line 3); Lee (line 2) and lee (line 4),,,,\r\n"))

        let html = Exporter.html(tests, workspaceName: "w", generated: Date())
        XCTAssertTrue(html.contains("<li class=\"info\"><span class=\"sev\">Key clash</span> Variant 2: Smith2025 (line 1) and Smith2025 (line 3)</li>"))
        XCTAssertTrue(html.contains("rowspan=\"3\">KC-2</th>"))
        XCTAssertFalse(html.contains("<span class=\"sev\">Warning</span>"))
    }

    func testGroundTruthAndAnnotationsInBothExports() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "GT-1")
        try ws.write("GT-1/GT-1_query/GT-1_annotation.md", "Tool missed <two> key papers.\n")
        try ws.write("GT-1/GT-1_ground_truth.bib",
                     "@article{t, author={Smith, John}, title={Truth}, journal={J}, year={2024}, doi={10.1234/abcd9999}}")
        let tests = try WorkspaceScanner.scan(ws.url).tests
        XCTAssertEqual(tests[0].status, .complete, tests[0].messages.joined(separator: "\n"))

        let csv = Exporter.csv(tests)
        XCTAssertTrue(csv.contains(",Complete,,,Tool missed <two> key papers.,\"Smith, J. (2024). Truth. J. doi:10.1234/abcd9999\",doi:10.1234/abcd9999,\r\n"))

        let html = Exporter.html(tests, workspaceName: "w", generated: Date())
        XCTAssertTrue(html.contains("<p class=\"note\">Tool missed &lt;two&gt; key papers.</p>"))
        XCTAssertTrue(html.contains("<span class=\"sev\">Ground truth</span> Smith, J. (2024). Truth. <i>J</i>. doi:10.1234/abcd9999</li>"))
        XCTAssertTrue(html.contains("rowspan=\"2\">GT-1</th>"))
    }

    func testExportDatesInCSVAndHTML() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "D-1", 1, skip: ["bib"])
        try writeVariant(ws, "D-1", 2, skip: ["bib"])
        try ws.write("D-1/D-1_variant1_references_n2.bib", "Scopus\nEXPORT DATE: 30 September 2026\n\n" + bibtex(2))
        try ws.write("D-1/D-1_variant2_references_n2.bib", "Scopus\nEXPORT DATE: 02 October 2026\n\n" + bibtex(2))
        let tests = try WorkspaceScanner.scan(ws.url).tests
        XCTAssertEqual(tests[0].dateText, "30 September \u{2013} 2 October 2026")

        let csv = Exporter.csv(tests)
        XCTAssertTrue(csv.contains(",Complete,,,,,,2026-09-30\r\n"))
        XCTAssertTrue(csv.contains(",Complete,,,,,,2026-10-02\r\n"))

        let html = Exporter.html(tests, workspaceName: "w", generated: Date())
        XCTAssertTrue(html.contains(">D-1<span class=\"date\">30 September \u{2013} 2 October 2026</span></th>"))
    }

    // MARK: Markdown

    func testMarkdownExport() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "MD-1", question: "What | why *and* <how>?\nSecond line", references: 3, namedCount: 4)
        try ws.write("MD-1/MD-1_ground_truth.bib",
                     "@article{t, author={Smith, John}, title={Truth}, journal={J of IS}, volume={7}, year={2024}, doi={10.1/x}}")
        try ws.write("MD-1/MD-1_query/MD-1_annotation.md", "Line one\nLine _two_")
        try writeVariant(ws, "MD-2", 1, skip: ["bib"])
        try writeVariant(ws, "MD-2", 2)
        try ws.write("MD-2/MD-2_variant1_references_n2.bib",
                     "EXPORT DATE: 1 October 2026\n@article{K`1,}\n@article{K`1,}\n")
        let tests = try WorkspaceScanner.scan(ws.url).tests
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let md = Exporter.markdown(tests, workspaceName: "Q3_runs", generated: date,
                                   timeZone: TimeZone(identifier: "UTC")!)

        XCTAssertTrue(md.hasPrefix("# Literature review test runs\n\nWorkspace **Q3\\_runs**, exported 2026-09-21 14:13.\n\n"))
        XCTAssertTrue(md.contains("**2 tests**: 1 complete, 0 with warnings, 1 with errors."))
        XCTAssertTrue(md.contains("| Test | Type | RQs | References | Export date | Ground truth | Status |\n| --- | --- | ---: | ---: | --- | --- | --- |\n"))
        XCTAssertTrue(md.contains("| [MD-1](#md-1) | Single RQ | 1 | 3 | \u{2013} | Smith (2024) | \u{274C} Errors |\n"))
        XCTAssertTrue(md.contains("| [MD-2](#md-2) | Multiple RQs | 2 | 2, 2 | 1 Oct 2026 |  | \u{2705} Complete |\n"))

        XCTAssertTrue(md.contains("\n## MD-1\n\n\u{274C} Errors, Single RQ, 3 references\n\n"))
        XCTAssertTrue(md.contains("**Ground truth:** Smith, J. (2024). Truth. *J of IS*, *7*. doi:10.1/x\n\n"))
        XCTAssertTrue(md.contains("| Research question | Found | Annotation |\n| --- | ---: | --- |\n"))
        XCTAssertTrue(md.contains("| What \\| why \\*and\\* \\<how\\>?<br>Second line | 3 | Line one<br>Line \\_two\\_ |\n"))
        XCTAssertFalse(md.contains("**Annotations**"))
        XCTAssertFalse(md.contains("In file name"))
        XCTAssertFalse(md.contains("| Export date |\n"))
        XCTAssertTrue(md.contains("- \u{274C} **Error:** MD-1\\_references\\_n4.bib: the file name says 4 references, but the file has 3\n"))

        XCTAssertTrue(md.contains("\n## MD-2\n\n\u{2705} Complete, Multiple RQs, 4 references, exported 1 Oct 2026\n\n"))
        XCTAssertTrue(md.contains("| Variant | Research question | Found | Annotation |\n| ---: | --- | ---: | --- |\n"))
        XCTAssertTrue(md.contains("| 1 | Question 1? | 2 | _(No annotation found.)_ |\n"))
        XCTAssertTrue(md.contains("**Key clashes** (for information)\n\n- Variant 1: `K\u{2018}1` (line 2) and `K\u{2018}1` (line 3)\n"))
        XCTAssertFalse(md.contains("<how>"))
    }

    func testMarkdownLinksToArtifacts() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "L-1")
        try ws.write("L-1/L-1_ground_truth.bib", "@article{t, author={Lee, Kim}, title={T}, year={2020}}")
        try ws.write("L-1/L-1_query/L-1_annotation.md", "Note")
        try writeVariant(ws, "L-2", 1)
        try writeVariant(ws, "L-2", 2, skip: ["dom"])
        let tests = try WorkspaceScanner.scan(ws.url).tests

        // Saved in the workspace as README.md: links start with the test folder.
        let md = Exporter.markdown(tests, workspaceName: "w", generated: Date(), linkBase: ws.url)
        XCTAssertTrue(md.contains("\n## L-1\n\n"))
        XCTAssertTrue(md.contains("**Folder:** [L-1/](L-1/)\n\n"))
        XCTAssertTrue(md.contains("**Ground truth:** Lee, K. (2020). T. ([BibTeX](L-1/L-1_ground_truth.bib))\n\n"))
        XCTAssertTrue(md.contains("**Files:** [query screenshot](L-1/L-1_query/L-1_query_asked.png), "
            + "[response screenshot](L-1/L-1_query/L-1_response_received.png), "
            + "[references BIB](L-1/L-1_references_n3.bib), "
            + "[report PDF](L-1/L-1_report.pdf), [report DOM (HTML)](L-1/L-1_report_DOM.html)\n\n"))
        XCTAssertFalse(md.contains("RQ_asked.md)"))
        XCTAssertFalse(md.contains("annotation.md)"))
        XCTAssertTrue(md.contains("| What is known about X? | 3 | Note |\n"))
        XCTAssertTrue(md.contains("**Files**\n\n- Variant 1: [query screenshot](L-2/L-2_query_variant1/L-2_variant1_query_asked.png), "))
        XCTAssertTrue(md.contains("- Variant 2: [query screenshot](L-2/L-2_query_variant2/L-2_variant2_query_asked.png), "))
        XCTAssertTrue(md.contains("[report PDF](L-2/L-2_variant2_report.pdf)\n"))
        XCTAssertFalse(md.contains("L-2_variant2_report_DOM.html)"))

        // Saved elsewhere, the links climb back to the workspace.
        try ws.makeFolder("exports")
        let elsewhere = Exporter.markdown(tests, workspaceName: "w", generated: Date(),
                                          linkBase: ws.url.appendingPathComponent("exports", isDirectory: true))
        XCTAssertTrue(elsewhere.contains("**Folder:** [L-1/](../L-1/)\n\n"))
        XCTAssertTrue(elsewhere.contains("[report PDF](../L-1/L-1_report.pdf)"))

        // Without a base there are no links.
        XCTAssertFalse(Exporter.markdown(tests, workspaceName: "w", generated: Date()).contains("**Folder:**"))
    }

    func testRelativeLinksAreEncoded() throws {
        let ws = try TempFolder()
        let file = try ws.write("Odd (1) [v2].pdf", "x")
        XCTAssertEqual(Exporter.relativeLink(from: ws.url, to: file), "Odd%20%281%29%20%5Bv2%5D.pdf")
    }

    func testEmptyWorkspaceMarkdown() {
        let md = Exporter.markdown([], workspaceName: "Empty", generated: Date())
        XCTAssertTrue(md.hasSuffix("This workspace has no tests yet.\n"))
        XCTAssertFalse(md.contains("| Test |"))
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
