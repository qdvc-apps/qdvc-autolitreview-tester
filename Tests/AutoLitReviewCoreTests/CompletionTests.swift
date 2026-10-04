import XCTest
@testable import AutoLitReviewCore

final class CompletionTests: XCTestCase {
    private func scanTest(_ ws: TempFolder, _ id: String) throws -> TestRun {
        try XCTUnwrap(try WorkspaceScanner.scan(ws.url).test(id))
    }

    func testSuppliesMissingArtifactsUnderStandardNames() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "C-1", references: 3, skip: ["response", "dom"])
        let response = try ws.write("elsewhere/Screenshot 2026-10-02 at 10.15.png", "png!")
        let dom = try ws.write("elsewhere/saved page.htm", "<html>dom</html>")
        let before = try ws.names(in: "C-1")

        let test = try scanTest(ws, "C-1")
        XCTAssertTrue(test.hasMissingArtifacts)
        var draft = CompletionDraft(test: test)
        XCTAssertEqual(draft.questions[0].missing, [.responseReceived, .reportDOM])
        XCTAssertEqual(draft.questions[0].existing[.queryAsked], "C-1_query/C-1_query_asked.png")
        XCTAssertFalse(draft.hasChanges)

        draft.questions[0].input.setFile(response, for: .responseReceived)
        XCTAssertTrue(draft.hasChanges)
        XCTAssertEqual(draft.stillMissingSummary, ["report DOM (HTML)"])
        draft.questions[0].input.setFile(dom, for: .reportDOM)
        XCTAssertEqual(draft.stillMissingSummary, [])
        XCTAssertEqual(draft.plannedFiles().map(\.relativePath),
                       ["C-1_query/C-1_response_received.png", "C-1_report_DOM.html"])

        XCTAssertEqual(try TestCreator.complete(draft, test: test), 2)
        let after = try scanTest(ws, "C-1")
        XCTAssertEqual(after.status, .complete, after.messages.joined(separator: "\n"))
        XCTAssertFalse(after.hasMissingArtifacts)
        XCTAssertTrue(Set(before).isSubset(of: Set(try ws.names(in: "C-1"))))
        // The originals are still where they were.
        XCTAssertEqual(try String(contentsOf: response, encoding: .utf8), "png!")
        XCTAssertTrue(ws.exists("elsewhere/saved page.htm"))
    }

    func testPartialSaveAndMissingReferencesAreCounted() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "C-2", skip: ["bib", "pdf"])
        let bib = try ws.write("src/refs.bib", bibtex(7))
        let test = try scanTest(ws, "C-2")
        var draft = CompletionDraft(test: test)
        draft.questions[0].input.setFile(bib, for: .references)
        XCTAssertEqual(draft.stillMissingSummary, ["report PDF"])
        try TestCreator.complete(draft, test: test)
        let after = try scanTest(ws, "C-2")
        XCTAssertEqual(after.questions[0].file(.references)?.name, "C-2_references_n7.bib")
        XCTAssertEqual(after.questions[0].countMatches, true)
        XCTAssertTrue(after.hasIssue(.error, containing: "Report (PDF) is missing"))
    }

    func testFillsAMissingOrEmptyResearchQuestionButNothingElseExisting() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "C-3", question: "   ")
        try writeSingleTest(ws, "C-4", skip: ["rq"])
        for id in ["C-3", "C-4"] {
            let test = try scanTest(ws, id)
            var draft = CompletionDraft(test: test)
            XCTAssertEqual(draft.questions[0].missing, [.rqText])
            draft.questions[0].input.text = "  Recovered question?  "
            try TestCreator.complete(draft, test: test)
            let after = try scanTest(ws, id)
            XCTAssertEqual(after.questions[0].question, "Recovered question?")
            XCTAssertEqual(after.status, .complete, after.messages.joined(separator: "\n"))
        }
    }

    func testNeverOverwritesAndCleansUpOnFailure() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "C-5", skip: ["pdf", "dom"])
        let test = try scanTest(ws, "C-5")
        var draft = CompletionDraft(test: test)
        draft.questions[0].input.setFile(try ws.write("src/r.pdf", "%PDF"), for: .report)
        let gone = ws.url.appendingPathComponent("src/gone.html")
        draft.questions[0].input.setFile(gone, for: .reportDOM)

        // The source of the second file is missing, so the first copy is undone.
        XCTAssertThrowsError(try TestCreator.complete(draft, test: test)) { error in
            guard case .failed? = error as? NewTestError else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertFalse(ws.exists("C-5/C-5_report.pdf"))

        // A file that appeared meanwhile is never written over.
        try ws.write("C-5/C-5_report.pdf", "someone else's")
        try ws.write("src/gone.html", "<html/>")
        XCTAssertThrowsError(try TestCreator.complete(draft, test: test)) { error in
            XCTAssertEqual(error as? NewTestError, .wouldOverwrite("C-5/C-5_report.pdf"))
        }
        XCTAssertEqual(try String(contentsOf: ws.url.appendingPathComponent("C-5/C-5_report.pdf"), encoding: .utf8),
                       "someone else's")
        XCTAssertFalse(ws.exists("C-5/C-5_report_DOM.html"))
    }

    func testVariantsOlderFoldersAndAnnotations() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "C-6", 1, skip: ["query"])
        // Variant 2 lives in an older-named folder and lacks its response screenshot.
        try ws.write("C-6/C-6_variant2/C-6_variant2_query_asked.png", "q")
        try ws.write("C-6/C-6_variant2/C-6_variant2_RQ_asked.md", "Q2?")
        try ws.write("C-6/C-6_variant2_references_n1.bib", bibtex(1))
        try ws.write("C-6/C-6_variant2_report.pdf", "%PDF")
        try ws.write("C-6/C-6_variant2_report_DOM.html", "<html/>")
        // Variant 3 has only its BibTeX file, so its query folder doesn't exist yet.
        try ws.write("C-6/C-6_variant3_references_n1.bib", bibtex(1))

        let test = try scanTest(ws, "C-6")
        var draft = CompletionDraft(test: test)
        XCTAssertEqual(draft.questions.map(\.queryFolder),
                       ["C-6_query_variant1", "C-6_variant2", "C-6_query_variant3"])
        draft.questions[0].input.setFile(try ws.write("s/q1.png", "q"), for: .queryAsked)
        draft.questions[0].input.annotation = "Annotated while completing"
        draft.questions[1].input.setFile(try ws.write("s/r2.png", "r"), for: .responseReceived)
        draft.questions[2].input.text = "Third?"
        XCTAssertEqual(draft.plannedFiles().map(\.relativePath), [
            "C-6_query_variant1/C-6_variant1_query_asked.png",
            "C-6_variant2/C-6_variant2_response_received.png",
            "C-6_query_variant3/C-6_variant3_RQ_asked.md",
        ])
        try TestCreator.complete(draft, test: test)

        let after = try scanTest(ws, "C-6")
        XCTAssertEqual(after.questions[0].status, .complete, "(the older folder name is a test-level warning)")
        XCTAssertEqual(after.questions[0].annotation, "Annotated while completing")
        XCTAssertNotNil(after.questions[1].file(.responseReceived))
        XCTAssertEqual(after.questions[2].question, "Third?")
    }

    func testAnnotationOnlyEditsOfACompleteTest() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "C-7")
        try ws.write("C-7/C-7_query/C-7_annotation.md", "Old note")
        let test = try scanTest(ws, "C-7")
        XCTAssertFalse(test.hasMissingArtifacts)
        var draft = CompletionDraft(test: test)
        XCTAssertFalse(draft.hasMissing)
        XCTAssertEqual(draft.questions[0].input.annotation, "Old note")
        draft.questions[0].input.annotation = "New note"
        XCTAssertTrue(draft.hasChanges)
        XCTAssertEqual(try TestCreator.complete(draft, test: test), 0)
        XCTAssertEqual(try scanTest(ws, "C-7").questions[0].annotation, "New note")
    }
}
