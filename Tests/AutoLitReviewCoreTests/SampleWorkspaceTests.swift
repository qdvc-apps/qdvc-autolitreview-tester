import XCTest
@testable import AutoLitReviewCore

/// Checks the app's reading of sample-workspace/ (made by
/// tools/make_sample_workspace.py, which describes each case).
final class SampleWorkspaceTests: XCTestCase {
    private var sampleWorkspace: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AutoLitReviewCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("sample-workspace", isDirectory: true)
    }

    func testSampleWorkspace() throws {
        let scan = try WorkspaceScanner.scan(sampleWorkspace)
        XCTAssertEqual(scan.tests.map(\.id), ["DEMO-101", "DEMO-102", "DEMO-103", "DEMO-104", "DEMO-105", "DEMO-110"])
        XCTAssertEqual(scan.otherItems, ["README.txt"])

        let status = Dictionary(uniqueKeysWithValues: scan.tests.map { ($0.id, $0.status) })
        XCTAssertEqual(status, [
            "DEMO-101": .complete, "DEMO-102": .complete, "DEMO-103": .errors,
            "DEMO-104": .warnings, "DEMO-105": .errors, "DEMO-110": .complete,
        ])

        let counts = scan.tests.map { $0.questions.map { $0.referencesFound ?? -1 } }
        XCTAssertEqual(counts, [[12], [8, 5, 11], [18], [4, 6], [9, 7, 3], [0]])
        XCTAssertEqual(scan.test("DEMO-105")?.questions.map(\.variant), [1, 2, 4])
        XCTAssertEqual(scan.test("DEMO-103")?.questions.first?.referencesInFileName, 20)
        XCTAssertEqual(scan.questionCount, 11)

        XCTAssertEqual(scan.test("DEMO-101")?.groundTruth?.doi, "doi:10.1016/j.jss.2023.111602")
        XCTAssertEqual(scan.test("DEMO-102")?.groundTruth?.shortCitation, "Haddad & Silva (2024)")
        XCTAssertEqual(scan.test("DEMO-102")?.questions.map { $0.annotation != nil }, [true, true, false])
        XCTAssertNil(scan.test("DEMO-103")?.groundTruth)

        for test in scan.tests where test.status == .complete {
            XCTAssertTrue(test.allIssues.isEmpty, "\(test.id): \(test.allIssues)")
        }
    }
}
