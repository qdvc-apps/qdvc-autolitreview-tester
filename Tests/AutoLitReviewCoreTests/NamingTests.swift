import XCTest
@testable import AutoLitReviewCore

final class NamingTests: XCTestCase {
    func testValidTestIDs() {
        XCTAssertTrue(Naming.isValidTestID("ABCD-123"))
        XCTAssertTrue(Naming.isValidTestID("123"))
        XCTAssertTrue(Naming.isValidTestID("A-B-C"))
        XCTAssertFalse(Naming.isValidTestID(""))
        XCTAssertFalse(Naming.isValidTestID("abcd-123"))
        XCTAssertFalse(Naming.isValidTestID("ABCD 123"))
        XCTAssertFalse(Naming.isValidTestID("ABCD_123"))
        XCTAssertFalse(Naming.isValidTestID("ÄBC-1"))
    }

    func testSanitizeUppercasesAndDropsTheRest() {
        XCTAssertEqual(Naming.sanitizeTestID("abcd-123").id, "ABCD-123")
        XCTAssertFalse(Naming.sanitizeTestID("abcd-123").removedSomething)
        let messy = Naming.sanitizeTestID("ab c_1é\t2")
        XCTAssertEqual(messy.id, "ABC12")
        XCTAssertTrue(messy.removedSomething)
        // Characters that uppercase to more than one letter are dropped, not expanded.
        XCTAssertEqual(Naming.sanitizeTestID("straße").id, "STRAE")
    }

    func testCanonicalNames() {
        XCTAssertEqual(Naming.queryFolderName(testID: "ABCD-123", variant: nil), "ABCD-123_query")
        XCTAssertEqual(Naming.queryFolderName(testID: "ABCD-123", variant: 2), "ABCD-123_query_variant2")
        XCTAssertEqual(Naming.fileName(.references, testID: "ABCD-123", variant: nil, referenceCount: 293),
                       "ABCD-123_references_n293.bib")
        XCTAssertEqual(Naming.fileName(.references, testID: "ABCD-123", variant: 1, referenceCount: 67),
                       "ABCD-123_variant1_references_n67.bib")
        XCTAssertEqual(Naming.fileName(.references, testID: "X", variant: nil), "X_references_n<count>.bib")
        XCTAssertEqual(Naming.fileName(.reportDOM, testID: "X", variant: 3), "X_variant3_report_DOM.html")
        XCTAssertEqual(Naming.relativePath(.queryAsked, testID: "ABCD-123", variant: nil),
                       "ABCD-123_query/ABCD-123_query_asked.png")
        XCTAssertEqual(Naming.relativePath(.rqText, testID: "ABCD-123", variant: 2),
                       "ABCD-123_query_variant2/ABCD-123_variant2_RQ_asked.md")
        XCTAssertEqual(Naming.relativePath(.report, testID: "ABCD-123", variant: 2), "ABCD-123_variant2_report.pdf")
    }

    func testNaturalOrder() {
        let ids = ["ABC-10", "ABC-2", "ABC-1", "AB-9", "ABC-02", "B-1", "ABC-2A"]
        XCTAssertEqual(ids.sorted(by: Naming.naturalLess),
                       ["AB-9", "ABC-1", "ABC-02", "ABC-2", "ABC-2A", "ABC-10", "B-1"])
        XCTAssertFalse(Naming.naturalLess("A", "A"))
    }

    func testTextHelpers() {
        XCTAssertEqual(TextSupport.list([]), "")
        XCTAssertEqual(TextSupport.list(["a"]), "a")
        XCTAssertEqual(TextSupport.list(["a", "b"]), "a and b")
        XCTAssertEqual(TextSupport.list(["a", "b", "c"]), "a, b and c")
        XCTAssertEqual(TextSupport.list(["a", "b", "c", "d"], limit: 2), "a, b and 2 more")
        XCTAssertEqual(TextSupport.plural(1, "reference"), "1 reference")
        XCTAssertEqual(TextSupport.plural(2, "entry", "entries"), "2 entries")
    }

    func testDateStamp() {
        let date = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC
        XCTAssertEqual(Naming.dateStamp(date, timeZone: TimeZone(identifier: "UTC")!), "2026-09-21")
    }
}
