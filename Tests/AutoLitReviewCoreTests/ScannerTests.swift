import XCTest
@testable import AutoLitReviewCore

final class ScannerTests: XCTestCase {
    private func scanOne(_ ws: TempFolder, _ id: String) throws -> TestRun {
        let scan = try WorkspaceScanner.scan(ws.url)
        return try XCTUnwrap(scan.test(id), "no test \(id) in \(scan.tests.map(\.id))")
    }

    // MARK: Complete tests

    func testCompleteSingleRQ() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "ABCD-123", question: "  What is known about X?\n\n", references: 4)
        let test = try scanOne(ws, "ABCD-123")
        XCTAssertEqual(test.kind, .single)
        XCTAssertEqual(test.status, .complete, test.messages.joined(separator: "\n"))
        XCTAssertEqual(test.questions.count, 1)
        let question = test.questions[0]
        XCTAssertNil(question.variant)
        XCTAssertEqual(question.question, "What is known about X?")
        XCTAssertEqual(question.referencesFound, 4)
        XCTAssertEqual(question.referencesInFileName, 4)
        XCTAssertEqual(question.countMatches, true)
        XCTAssertEqual(question.files.map(\.kind), ArtifactKind.allCases)
        XCTAssertEqual(question.file(.references)?.name, "ABCD-123_references_n4.bib")
        XCTAssertEqual(test.totalReferences, 4)
    }

    func testCompleteMultiRQ() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "ABCD-124", 1, references: 3)
        try writeVariant(ws, "ABCD-124", 2, references: 0)
        try writeVariant(ws, "ABCD-124", 3, references: 7)
        let test = try scanOne(ws, "ABCD-124")
        XCTAssertEqual(test.kind, .multi)
        XCTAssertEqual(test.status, .complete, test.messages.joined(separator: "\n"))
        XCTAssertEqual(test.questions.map(\.variant), [1, 2, 3])
        XCTAssertEqual(test.questions.map(\.referencesFound), [3, 0, 7])
        XCTAssertEqual(test.questions.map(\.question), ["Question 1?", "Question 2?", "Question 3?"])
        XCTAssertEqual(test.totalReferences, 10)
    }

    // MARK: Errors

    func testMissingArtifactsAreErrors() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-1", skip: ["dom", "response"])
        let test = try scanOne(ws, "T-1")
        XCTAssertEqual(test.status, .errors)
        XCTAssertTrue(test.hasIssue(.error, containing: "Report (HTML DOM) is missing (expected T-1_report_DOM.html)"))
        XCTAssertTrue(test.hasIssue(.error, containing:
            "Response screenshot is missing (expected T-1_query/T-1_response_received.png)"))
        XCTAssertEqual(test.questions[0].files.count, 4)
    }

    func testEmptyTestFolderIsSingleWithEverythingMissing() throws {
        let ws = try TempFolder()
        try ws.makeFolder("EMPTY-1")
        let test = try scanOne(ws, "EMPTY-1")
        XCTAssertEqual(test.kind, .single)
        XCTAssertEqual(test.questions[0].issues.filter { $0.severity == .error }.count, 6)
    }

    func testCountMismatchIsAnError() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-2", references: 18, namedCount: 20)
        let test = try scanOne(ws, "T-2")
        XCTAssertEqual(test.status, .errors)
        XCTAssertEqual(test.questions[0].countMatches, false)
        XCTAssertEqual(test.questions[0].referencesFound, 18)
        XCTAssertEqual(test.questions[0].referencesInFileName, 20)
        XCTAssertTrue(test.hasIssue(.error, containing: "T-2_references_n20.bib: the file name says 20 references, but the file has 18"))
    }

    func testReferencesWithoutCountInName() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-3", skip: ["bib"])
        try ws.write("T-3/T-3_references.bib", bibtex(2))
        let test = try scanOne(ws, "T-3")
        XCTAssertTrue(test.hasIssue(.error, containing: "T-3_references.bib has no reference count in its name"))
        XCTAssertEqual(test.questions[0].referencesFound, 2)
        XCTAssertNil(test.questions[0].referencesInFileName)
        XCTAssertNil(test.questions[0].countMatches)
    }

    func testTwoReferenceFilesAreAnError() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-4", references: 3)
        try ws.write("T-4/T-4_references_n5.bib", bibtex(5))
        let test = try scanOne(ws, "T-4")
        XCTAssertTrue(test.hasIssue(.error, containing: "More than one references file: T-4_references_n3.bib and T-4_references_n5.bib"))
    }

    func testEmptyResearchQuestionIsAnError() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-5", question: "  \n ")
        let test = try scanOne(ws, "T-5")
        XCTAssertNil(test.questions[0].question)
        XCTAssertTrue(test.hasIssue(.error, containing: "The research question file is empty"))
    }

    // MARK: Warnings

    func testZeroByteFileIsAWarning() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-6", skip: ["pdf"])
        try ws.write("T-6/T-6_report.pdf", "")
        let test = try scanOne(ws, "T-6")
        XCTAssertEqual(test.status, .warnings)
        XCTAssertTrue(test.hasIssue(.warning, containing: "T-6_report.pdf is empty (0 bytes)"))
    }

    func testOlderVariantNamesAreAcceptedWithWarnings() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "OLD-1", 1)
        // Variant 2 the older way: no "query_" on the folder, "query_" on the BibTeX file.
        try ws.write("OLD-1/OLD-1_variant2/OLD-1_variant2_query_asked.png", "png")
        try ws.write("OLD-1/OLD-1_variant2/OLD-1_variant2_response_received.png", "png")
        try ws.write("OLD-1/OLD-1_variant2/OLD-1_variant2_RQ_asked.md", "Second?")
        try ws.write("OLD-1/OLD-1_query_variant2_references_n2.bib", bibtex(2))
        try ws.write("OLD-1/OLD-1_variant2_report.pdf", "%PDF")
        try ws.write("OLD-1/OLD-1_variant2_report_DOM.html", "<html/>")
        let test = try scanOne(ws, "OLD-1")
        XCTAssertEqual(test.kind, .multi)
        XCTAssertEqual(test.status, .warnings, test.messages.joined(separator: "\n"))
        XCTAssertEqual(test.questions.map(\.variant), [1, 2])
        XCTAssertEqual(test.questions[1].question, "Second?")
        XCTAssertEqual(test.questions[1].referencesFound, 2)
        XCTAssertEqual(test.questions[1].countMatches, true)
        XCTAssertTrue(test.hasIssue(.warning, containing: "Folder OLD-1_variant2 doesn\u{2019}t follow the naming convention; expected OLD-1_query_variant2"))
        XCTAssertTrue(test.hasIssue(.warning, containing: "OLD-1_query_variant2_references_n2.bib doesn\u{2019}t follow the naming convention; expected OLD-1_variant2_references_n2.bib"))
    }

    func testCanonicalNameIsPreferredOverAnAlias() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "DUP-1", 1, references: 2)
        try writeVariant(ws, "DUP-1", 2, references: 2)
        try ws.write("DUP-1/DUP-1_query_variant2_references_n9.bib", bibtex(9))
        let test = try scanOne(ws, "DUP-1")
        XCTAssertEqual(test.questions[1].file(.references)?.name, "DUP-1_variant2_references_n2.bib")
        XCTAssertTrue(test.hasIssue(.error, containing: "More than one references file"))
    }

    func testVariantNumberingProblems() throws {
        let ws = try TempFolder()
        for variant in [1, 2, 4] { try writeVariant(ws, "GAP-1", variant) }
        try writeVariant(ws, "ONE-1", 1)
        for variant in [1, 3, 5] { try writeVariant(ws, "GAP-2", variant) }

        let gap = try scanOne(ws, "GAP-1")
        XCTAssertEqual(gap.status, .warnings)
        XCTAssertEqual(gap.questions.map(\.variant), [1, 2, 4])
        XCTAssertTrue(gap.hasIssue(.warning, containing: "Variant numbering has a gap: no variant 3"))

        let gaps = try scanOne(ws, "GAP-2")
        XCTAssertTrue(gaps.hasIssue(.warning, containing: "no variants 2 and 4"))

        let one = try scanOne(ws, "ONE-1")
        XCTAssertEqual(one.kind, .multi)
        XCTAssertTrue(one.hasIssue(.warning, containing: "Only one variant was found"))
    }

    func testVariantWithOnlySomeFilesStillGetsARow() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "PART-1", 1)
        try writeVariant(ws, "PART-1", 2)
        try ws.write("PART-1/PART-1_variant3_references_n1.bib", bibtex(1))
        let test = try scanOne(ws, "PART-1")
        XCTAssertEqual(test.questions.map(\.variant), [1, 2, 3])
        XCTAssertEqual(test.questions[2].referencesFound, 1)
        XCTAssertEqual(test.questions[2].issues.filter { $0.severity == .error }.count, 5)
        XCTAssertEqual(test.rowStatus(test.questions[0]), .complete)
        XCTAssertEqual(test.rowStatus(test.questions[2]), .errors)
    }

    func testStrayAndMisplacedItems() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-7")
        try ws.write("T-7/notes.txt", "my notes")
        try ws.write("T-7/T-7_query_asked.png", "png")
        try ws.write("T-7/T-7_query/extra.png", "png")
        try ws.write("T-7/T-7_query/T-7_variant2_RQ_asked.md", "wrong folder")
        try ws.write("T-7/.DS_Store", "hidden")
        try ws.makeFolder("T-7/drafts")
        let test = try scanOne(ws, "T-7")
        XCTAssertEqual(test.kind, .single)
        XCTAssertEqual(test.status, .warnings, test.messages.joined(separator: "\n"))
        XCTAssertTrue(test.hasIssue(.warning, containing: "Unrecognised item: notes.txt"))
        XCTAssertTrue(test.hasIssue(.warning, containing: "Unrecognised item: drafts"))
        XCTAssertTrue(test.hasIssue(.warning, containing: "T-7_query_asked.png is in the test folder; it belongs in T-7_query/"))
        XCTAssertTrue(test.hasIssue(.warning, containing: "Unrecognised item: T-7_query/extra.png"))
        XCTAssertTrue(test.hasIssue(.warning, containing: "T-7_query/T-7_variant2_RQ_asked.md is named for variant 2"))
        XCTAssertFalse(test.messages.contains { $0.contains("DS_Store") })
    }

    func testVariantsAndSingleItemsTogether() throws {
        let ws = try TempFolder()
        try writeVariant(ws, "MIX-1", 1)
        try writeVariant(ws, "MIX-1", 2)
        try ws.write("MIX-1/MIX-1_report.pdf", "%PDF")
        try ws.write("MIX-1/MIX-1_query/MIX-1_RQ_asked.md", "Single?")
        let test = try scanOne(ws, "MIX-1")
        XCTAssertEqual(test.kind, .multi)
        XCTAssertEqual(test.questions.count, 2)
        XCTAssertTrue(test.hasIssue(.warning, containing: "also single-RQ items: MIX-1_query/ and MIX-1_report.pdf"))
    }

    func testBibTeXWarnings() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "T-8", skip: ["bib"])
        try ws.write("T-8/T-8_references_n3.bib", "@article{a, x={1}}\n@article{A, x={2}}\n@article{, x={3}")
        let test = try scanOne(ws, "T-8")
        XCTAssertEqual(test.questions[0].referencesFound, 3)
        XCTAssertEqual(test.status, .warnings, test.messages.joined(separator: "\n"))
        // The clashing keys a and A are listed, not raised as an issue.
        XCTAssertEqual(test.questions[0].keyClashes.map(\.description), ["a (line 1) and A (line 2)"])
        XCTAssertFalse(test.messages.contains { $0.lowercased().contains("citation keys") })
        XCTAssertTrue(test.hasIssue(.warning, containing: "1 entry without a citation key"))
        XCTAssertTrue(test.hasIssue(.warning, containing: "ends inside an entry"))
    }

    func testKeyClashesAloneLeaveATestComplete() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "KC-1", skip: ["bib"])
        try ws.write("KC-1/KC-1_references_n3.bib",
                     "@article{Smith2025, title={A}}\n@article{Lee2024, title={B}}\n@article{Smith2025, title={C}}\n")
        let test = try scanOne(ws, "KC-1")
        XCTAssertEqual(test.status, .complete, test.messages.joined(separator: "\n"))
        XCTAssertTrue(test.allIssues.isEmpty)
        XCTAssertEqual(test.questions[0].referencesFound, 3)
        XCTAssertEqual(test.questions[0].keyClashes.map(\.description), ["Smith2025 (line 1) and Smith2025 (line 3)"])
    }

    func testKeysWithSpacesStillCountAndMatch() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "SP-1", skip: ["bib"])
        try ws.write("SP-1/SP-1_references_n2.bib",
                     "@article{Smith 2020, title={A}}\n@inproceedings{van der Berg 2021, title={B}}\n")
        let test = try scanOne(ws, "SP-1")
        XCTAssertEqual(test.questions[0].referencesFound, 2)
        XCTAssertEqual(test.status, .complete, test.messages.joined(separator: "\n"))
    }

    // MARK: Ground truth and annotations

    func testGroundTruthAndAnnotationsAreOptionalAndRecognised() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "GT-2")
        try ws.write("GT-2/GT-2_ground_truth.bib", "@article{t, author={Lee, Kim}, title={T}, year={2020}, doi={https://doi.org/10.1/x}}")
        try ws.write("GT-2/GT-2_query/GT-2_annotation.md", "\n  Looks good.  \n")
        try writeVariant(ws, "GT-3", 1)
        try writeVariant(ws, "GT-3", 2)
        try ws.write("GT-3/GT-3_ground_truth.bib", "@book{b, title={B}}")
        try ws.write("GT-3/GT-3_query_variant2/GT-3_variant2_annotation.md", "Second variant note")
        try writeSingleTest(ws, "GT-4")

        let scan = try WorkspaceScanner.scan(ws.url)
        let single = try XCTUnwrap(scan.test("GT-2"))
        XCTAssertEqual(single.status, .complete, single.messages.joined(separator: "\n"))
        XCTAssertEqual(single.groundTruth?.doi, "doi:10.1/x")
        XCTAssertEqual(single.groundTruth?.shortCitation, "Lee (2020)")
        XCTAssertEqual(single.questions[0].annotation, "Looks good.")
        XCTAssertEqual(single.questions[0].annotationFile?.lastPathComponent, "GT-2_annotation.md")

        let multi = try XCTUnwrap(scan.test("GT-3"))
        XCTAssertEqual(multi.status, .complete, multi.messages.joined(separator: "\n"))
        XCTAssertNotNil(multi.groundTruth)
        XCTAssertNil(multi.questions[0].annotation)
        XCTAssertEqual(multi.questions[1].annotation, "Second variant note")

        let none = try XCTUnwrap(scan.test("GT-4"))
        XCTAssertNil(none.groundTruth)
        XCTAssertEqual(none.status, .complete)
    }

    func testGroundTruthWithSeveralEntriesIsAWarning() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "GT-5")
        try ws.write("GT-5/GT-5_ground_truth.bib", "@article{a, title={A}}\n@article{b, title={B}}\n")
        let test = try scanOne(ws, "GT-5")
        XCTAssertEqual(test.status, .warnings)
        XCTAssertTrue(test.hasIssue(.warning, containing: "GT-5_ground_truth.bib: It holds 2 entries"))
        XCTAssertEqual(test.groundTruth?.entry?.key, "a")
    }

    func testWritingAnnotationsAndGroundTruth() throws {
        let ws = try TempFolder()
        try writeSingleTest(ws, "W-1")
        // Variant 2 in the older-named folder: its annotation goes beside its files.
        try writeVariant(ws, "W-2", 1)
        try ws.write("W-2/W-2_variant2/W-2_variant2_RQ_asked.md", "Q2?")
        var test = try scanOne(ws, "W-1")

        try WorkspaceWriter.saveAnnotation("  First note \n", for: test.questions[0], in: test)
        XCTAssertEqual(try String(contentsOf: ws.url.appendingPathComponent("W-1/W-1_query/W-1_annotation.md"), encoding: .utf8),
                       "First note\n")
        try WorkspaceWriter.saveGroundTruth("@article{x, title={X}}", for: test)
        XCTAssertTrue(ws.exists("W-1/W-1_ground_truth.bib"))

        test = try scanOne(ws, "W-1")
        XCTAssertEqual(test.questions[0].annotation, "First note")
        XCTAssertEqual(test.status, .complete, test.messages.joined(separator: "\n"))

        // Empty text removes the files.
        try WorkspaceWriter.saveAnnotation("   ", for: test.questions[0], in: test)
        try WorkspaceWriter.saveGroundTruth("", for: test)
        XCTAssertFalse(ws.exists("W-1/W-1_query/W-1_annotation.md"))
        XCTAssertFalse(ws.exists("W-1/W-1_ground_truth.bib"))

        let old = try scanOne(ws, "W-2")
        try WorkspaceWriter.saveAnnotation("Older folder", for: old.questions[1], in: old)
        XCTAssertTrue(ws.exists("W-2/W-2_variant2/W-2_variant2_annotation.md"))
        XCTAssertEqual(try scanOne(ws, "W-2").questions[1].annotation, "Older folder")

        // A question with no query folder yet gets the standard one.
        try ws.makeFolder("W-3")
        let empty = try scanOne(ws, "W-3")
        try WorkspaceWriter.saveAnnotation("Nothing here yet", for: empty.questions[0], in: empty)
        XCTAssertTrue(ws.exists("W-3/W-3_query/W-3_annotation.md"))
    }

    // MARK: Workspace

    func testWorkspaceListsTestsInNaturalOrderAndOtherItems() throws {
        let ws = try TempFolder()
        for id in ["ABC-10", "ABC-2", "ABC-1"] { try writeSingleTest(ws, id) }
        try ws.makeFolder("lowercase-1")
        try ws.makeFolder("HAS SPACE")
        try ws.write("export.csv", "a,b")
        try ws.write("ABC-99", "a file, not a folder")
        try ws.makeFolder(".ABC-3.creating-1234")
        let scan = try WorkspaceScanner.scan(ws.url)
        XCTAssertEqual(scan.tests.map(\.id), ["ABC-1", "ABC-2", "ABC-10"])
        XCTAssertEqual(scan.otherItems, ["ABC-99", "export.csv", "HAS SPACE", "lowercase-1"])
        XCTAssertEqual(scan.questionCount, 3)
    }

    func testMissingWorkspaceThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")
        XCTAssertThrowsError(try WorkspaceScanner.scan(missing))
    }

    func testNameParsing() {
        typealias P = WorkspaceScanner.ParsedName
        XCTAssertNil(WorkspaceScanner.parse("OTHER_query", testID: "ID"))
        XCTAssertEqual(WorkspaceScanner.parse("ID_query", testID: "ID"), P(variant: nil, rest: "query"))
        XCTAssertEqual(WorkspaceScanner.parse("ID_query_variant2", testID: "ID"),
                       P(variant: 2, queryPrefix: true, plainDigits: true, rest: ""))
        XCTAssertEqual(WorkspaceScanner.parse("ID_variant12_report.pdf", testID: "ID"),
                       P(variant: 12, queryPrefix: false, plainDigits: true, rest: "report.pdf"))
        XCTAssertEqual(WorkspaceScanner.parse("ID_variant03_report.pdf", testID: "ID"),
                       P(variant: 3, queryPrefix: false, plainDigits: false, rest: "report.pdf"))
        XCTAssertEqual(WorkspaceScanner.parse("ID_variants.txt", testID: "ID"), P(variant: nil, rest: "variants.txt"))
        XCTAssertEqual(WorkspaceScanner.parse("ID_variant2x", testID: "ID"), P(variant: nil, rest: "variant2x"))

        XCTAssertEqual(WorkspaceScanner.parseTopLevel("references_n293.bib")?.count, 293)
        XCTAssertEqual(WorkspaceScanner.parseTopLevel("references_n293.bib")?.kind, .references)
        XCTAssertEqual(WorkspaceScanner.parseTopLevel("references.bib")?.kind, .references)
        XCTAssertNil(WorkspaceScanner.parseTopLevel("references.bib")?.count)
        XCTAssertNil(WorkspaceScanner.parseTopLevel("references_nX.bib")?.count)
        XCTAssertEqual(WorkspaceScanner.parseTopLevel("report.pdf")?.kind, .report)
        XCTAssertEqual(WorkspaceScanner.parseTopLevel("report_DOM.html")?.kind, .reportDOM)
        XCTAssertNil(WorkspaceScanner.parseTopLevel("report.PDF"))
        XCTAssertNil(WorkspaceScanner.parseTopLevel("summary.pdf"))
    }
}
