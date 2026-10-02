import XCTest
@testable import AutoLitReviewCore

final class NewTestTests: XCTestCase {
    /// Source files somewhere outside the workspace, named the way a tester
    /// might have them.
    private func sources(_ folder: TempFolder, _ tag: String, references: Int) throws -> [ArtifactKind: URL] {
        [
            .queryAsked: try folder.write("src/\(tag) query.png", "q-\(tag)"),
            .responseReceived: try folder.write("src/\(tag) response.png", "r-\(tag)"),
            .references: try folder.write("src/\(tag).bib", bibtex(references)),
            .report: try folder.write("src/\(tag).pdf", "%PDF \(tag)"),
            .reportDOM: try folder.write("src/\(tag).htm", "<html>\(tag)</html>"),
        ]
    }

    private func fill(_ question: inout DraftQuestion, _ files: [ArtifactKind: URL]) {
        for (kind, url) in files { question.setFile(url, for: kind) }
    }

    private let nothingExists: (String) -> Bool = { _ in false }

    // MARK: Validation

    func testEmptyDraftProblems() {
        let draft = NewTestDraft()
        XCTAssertEqual(draft.problems(exists: nothingExists), [
            "Enter a test ID",
            "Enter the research question",
            "Add the query screenshot, response screenshot, references file, report PDF and report DOM (HTML)",
        ])
    }

    func testIDProblems() {
        var draft = NewTestDraft()
        draft.id = "ab c"
        XCTAssertEqual(draft.idProblem(exists: nothingExists), "Test IDs use only A\u{2013}Z, 0\u{2013}9 and dashes")
        draft.id = "ABCD-123"
        XCTAssertNil(draft.idProblem(exists: nothingExists))
        XCTAssertEqual(draft.idProblem(exists: { $0 == "ABCD-123" }),
                       "A test called ABCD-123 already exists in this workspace")
    }

    func testMultiNeedsTwoQuestionsAndKeepsThemWhenSwitching() {
        var draft = NewTestDraft()
        draft.questions[0].text = "First"
        draft.kind = .multi
        XCTAssertEqual(draft.questions.count, 2)
        XCTAssertFalse(draft.canRemoveVariant)
        draft.addVariant()
        XCTAssertTrue(draft.canRemoveVariant)
        draft.removeVariant(draft.questions[1].id)
        XCTAssertEqual(draft.questions.count, 2)
        draft.questions[1].text = "Second"
        draft.kind = .single
        XCTAssertEqual(draft.activeQuestions.map(\.text), ["First"])
        draft.kind = .multi
        XCTAssertEqual(draft.activeQuestions.map(\.text), ["First", "Second"])

        let problems = draft.problems(exists: nothingExists)
        XCTAssertTrue(problems.contains { $0.hasPrefix("Variant 1: add the query screenshot") })
        XCTAssertTrue(problems.contains { $0.hasPrefix("Variant 2: add the query screenshot") })
    }

    func testReferencesAreCountedWhenChosen() throws {
        let folder = try TempFolder()
        var question = DraftQuestion()
        question.setFile(try folder.write("refs.bib", bibtex(7)), for: .references)
        XCTAssertEqual(question.referenceSummary?.entries, 7)
        question.setFile(folder.url.appendingPathComponent("missing.bib"), for: .references)
        XCTAssertNil(question.referenceSummary)
        XCTAssertNotNil(question.referenceError)
        question.setFile(nil, for: .references)
        XCTAssertNil(question.referenceError)
        XCTAssertTrue(question.missingFiles.contains(.references))
    }

    // MARK: Plan and create

    func testPlannedNamesForMultiRQ() throws {
        let folder = try TempFolder()
        var draft = NewTestDraft()
        draft.id = "ABCD-123"
        draft.kind = .multi
        draft.questions[0].text = "  First?  "
        let one = try sources(folder, "one", references: 67)
        let two = try sources(folder, "two", references: 23)
        fill(&draft.questions[0], one)
        fill(&draft.questions[1], two)
        draft.questions[1].text = "Second?"
        XCTAssertEqual(draft.plannedFiles().map(\.relativePath), [
            "ABCD-123_query_variant1/ABCD-123_variant1_query_asked.png",
            "ABCD-123_query_variant1/ABCD-123_variant1_response_received.png",
            "ABCD-123_query_variant1/ABCD-123_variant1_RQ_asked.md",
            "ABCD-123_variant1_references_n67.bib",
            "ABCD-123_variant1_report.pdf",
            "ABCD-123_variant1_report_DOM.html",
            "ABCD-123_query_variant2/ABCD-123_variant2_query_asked.png",
            "ABCD-123_query_variant2/ABCD-123_variant2_response_received.png",
            "ABCD-123_query_variant2/ABCD-123_variant2_RQ_asked.md",
            "ABCD-123_variant2_references_n23.bib",
            "ABCD-123_variant2_report.pdf",
            "ABCD-123_variant2_report_DOM.html",
        ])
        XCTAssertEqual(draft.plannedFiles()[2].source, .text("First?\n"))
        XCTAssertEqual(draft.plannedFiles(testID: "TEST-ID").first?.relativePath,
                       "TEST-ID_query_variant1/TEST-ID_variant1_query_asked.png")
    }

    func testCreateCopiesWithoutTouchingOriginals() throws {
        let folder = try TempFolder()
        try folder.makeFolder("workspace")
        let workspace = folder.url.appendingPathComponent("workspace", isDirectory: true)
        let files = try sources(folder, "orig", references: 5)
        let before = try files.mapValues { try Data(contentsOf: $0) }

        var draft = NewTestDraft()
        draft.id = "NEW-1"
        draft.questions[0].text = "Is this a question?"
        fill(&draft.questions[0], files)
        XCTAssertEqual(draft.problems(exists: nothingExists), [])

        let created = try TestCreator.create(draft, in: workspace)
        XCTAssertEqual(created.lastPathComponent, "NEW-1")

        // Originals are still there, unchanged.
        for (kind, url) in files {
            XCTAssertEqual(try Data(contentsOf: url), before[kind], "\(kind) changed")
        }
        XCTAssertEqual(try Data(contentsOf: created.appendingPathComponent("NEW-1_report_DOM.html")),
                       before[.reportDOM])

        // The new test scans as complete, and nothing hidden is left behind.
        let scan = try WorkspaceScanner.scan(workspace)
        XCTAssertEqual(scan.tests.map(\.id), ["NEW-1"])
        let test = scan.tests[0]
        XCTAssertEqual(test.status, .complete, test.messages.joined(separator: "\n"))
        XCTAssertEqual(test.questions[0].question, "Is this a question?")
        XCTAssertEqual(test.questions[0].file(.references)?.name, "NEW-1_references_n5.bib")
        XCTAssertEqual(try folder.names(in: "workspace"), ["NEW-1"])
    }

    func testCreateCountsTheBibTeXAgain() throws {
        let folder = try TempFolder()
        try folder.makeFolder("workspace")
        let workspace = folder.url.appendingPathComponent("workspace", isDirectory: true)
        let files = try sources(folder, "grow", references: 2)
        var draft = NewTestDraft()
        draft.id = "GROW-1"
        draft.questions[0].text = "Q?"
        fill(&draft.questions[0], files)
        try Data(bibtex(9).utf8).write(to: files[.references]!)
        try TestCreator.create(draft, in: workspace)
        XCTAssertTrue(folder.exists("workspace/GROW-1/GROW-1_references_n9.bib"))
    }

    func testCreateRefusesAnExistingTest() throws {
        let folder = try TempFolder()
        try folder.makeFolder("workspace/OLD-1")
        let workspace = folder.url.appendingPathComponent("workspace", isDirectory: true)
        var draft = NewTestDraft()
        draft.id = "OLD-1"
        draft.questions[0].text = "Q?"
        let files = try sources(folder, "x", references: 1)
        fill(&draft.questions[0], files)
        XCTAssertThrowsError(try TestCreator.create(draft, in: workspace)) { error in
            XCTAssertEqual(error as? NewTestError, .alreadyExists("OLD-1"))
        }
        XCTAssertEqual(try folder.names(in: "workspace/OLD-1"), [])
    }

    func testCreateRefusesAnIncompleteDraft() throws {
        let folder = try TempFolder()
        var draft = NewTestDraft()
        draft.id = "INC-1"
        XCTAssertThrowsError(try TestCreator.create(draft, in: folder.url)) { error in
            guard case .notReady(let problems)? = error as? NewTestError else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(problems.first, "Enter the research question")
        }
    }

    func testFailedCopyLeavesNothingBehind() throws {
        let folder = try TempFolder()
        try folder.makeFolder("workspace")
        let workspace = folder.url.appendingPathComponent("workspace", isDirectory: true)
        let files = try sources(folder, "gone", references: 1)
        var draft = NewTestDraft()
        draft.id = "FAIL-1"
        draft.questions[0].text = "Q?"
        fill(&draft.questions[0], files)
        try FileManager.default.removeItem(at: files[.report]!)
        XCTAssertThrowsError(try TestCreator.create(draft, in: workspace)) { error in
            guard case .failed? = error as? NewTestError else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertEqual(try folder.names(in: "workspace"), [])
    }

    // MARK: Drop routing

    func testRoutingByExtensionAndName() {
        let urls = [
            "/x/ABCD-123_variant1_response_received.png", "/x/ABCD-123_variant1_query_asked.png",
            "/x/refs.BIB", "/x/report.pdf", "/x/page.HTML", "/x/rq.md", "/x/photo.jpg",
        ].map { URL(fileURLWithPath: $0) }
        let result = DropRouting.route(urls)
        XCTAssertEqual(result.assignments.map(\.kind), [.responseReceived, .queryAsked, .references, .report, .reportDOM])
        XCTAssertEqual(result.questionText?.lastPathComponent, "rq.md")
        XCTAssertEqual(result.rejected.map(\.lastPathComponent), ["photo.jpg"])
    }

    func testSingleScreenshotGoesWhereItWasDropped() {
        let url = URL(fileURLWithPath: "/x/Screenshot 2026-10-02.png")
        XCTAssertEqual(DropRouting.route([url], preferring: .responseReceived).assignments.map(\.kind),
                       [.responseReceived])
        // Dropped on a slot of another type, it goes to the first empty screenshot slot.
        XCTAssertEqual(DropRouting.route([url], preferring: .report,
                                         current: [.queryAsked: URL(fileURLWithPath: "/y.png")]).assignments.map(\.kind),
                       [.responseReceived])
    }

    func testTwoUnnamedScreenshotsFillBothSlots() {
        let urls = ["/x/Screenshot 1.png", "/x/Screenshot 2.png"].map { URL(fileURLWithPath: $0) }
        XCTAssertEqual(DropRouting.route(urls).assignments.map(\.kind), [.queryAsked, .responseReceived])
        let three = urls + [URL(fileURLWithPath: "/x/Screenshot 3.png")]
        XCTAssertEqual(DropRouting.route(three).rejected.map(\.lastPathComponent), ["Screenshot 3.png"])
    }
}
