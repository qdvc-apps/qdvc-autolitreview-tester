import XCTest
@testable import AutoLitReviewCore

final class DOMChecksTests: XCTestCase {
    // MARK: YAML

    func testMiniYAML() throws {
        let yaml = try MiniYAML.parse("""
        # A comment
        ---
        name: "Q3 runs"   # trailing comment
        note: it's fine # apostrophes are letters
        dom_checks:
          rq_text_string_check: True
          all_n_references_check: 'false'
          nested:
            deeper: yes
        flow: {a: 1, b: "two, three"}
        list:
          - first
          - "second"
        inline: [x, y]
        empty:
        """)
        XCTAssertEqual(yaml["name"]?.string, "Q3 runs")
        XCTAssertEqual(yaml["note"]?.string, "it's fine")
        XCTAssertEqual(yaml["dom_checks"]?["rq_text_string_check"]?.bool, true)
        XCTAssertEqual(yaml["dom_checks"]?["all_n_references_check"]?.bool, false)
        XCTAssertEqual(yaml["dom_checks"]?["nested"]?["deeper"]?.bool, true)
        XCTAssertEqual(yaml["flow"]?["b"]?.string, "two, three")
        XCTAssertEqual(yaml["list"], .sequence([.scalar("first"), .scalar("second")]))
        XCTAssertEqual(yaml["inline"], .sequence([.scalar("x"), .scalar("y")]))
        XCTAssertEqual(yaml["empty"]?.string, "")
        XCTAssertEqual(try MiniYAML.parse(""), .mapping([:]))
    }

    func testMiniYAMLErrors() {
        XCTAssertThrowsError(try MiniYAML.parse("dom_checks:\n  a: True\n    b: True\n")) { error in
            XCTAssertEqual((error as? YAMLError)?.line, 3)
        }
        XCTAssertThrowsError(try MiniYAML.parse("just a sentence\n"))
        XCTAssertThrowsError(try MiniYAML.parse("a: {b: 1\n"))
    }

    // MARK: Config

    func testConfig() {
        let both = WorkspaceConfig(yaml: "dom_checks:\n  rq_text_string_check: True\n  all_n_references_check: \"True\"\n")
        XCTAssertTrue(both.rqTextStringCheck)
        XCTAssertTrue(both.allNReferencesCheck)
        XCTAssertTrue(both.problems.isEmpty)

        let flow = WorkspaceConfig(yaml: "dom_checks: {rq_text_string_check: true}")
        XCTAssertTrue(flow.rqTextStringCheck)
        XCTAssertFalse(flow.allNReferencesCheck)

        let off = WorkspaceConfig(yaml: "dom_checks:\n  rq_text_string_check: False\nother: 1\n")
        XCTAssertFalse(off.anyDOMCheck)
        XCTAssertTrue(off.problems.isEmpty)

        XCTAssertFalse(WorkspaceConfig(yaml: "other: 1").anyDOMCheck)

        let odd = WorkspaceConfig(yaml: "dom_checks:\n  rq_text_string_check: maybe\n")
        XCTAssertFalse(odd.rqTextStringCheck)
        XCTAssertEqual(odd.problems, ["dom_checks.rq_text_string_check is \u{201C}maybe\u{201D}; use True or False"])

        let broken = WorkspaceConfig(yaml: "dom_checks:\n  rq_text_string_check: True\n    oops: x\n")
        XCTAssertFalse(broken.anyDOMCheck)
        XCTAssertEqual(broken.problems.count, 1)
    }

    // MARK: DOM text

    func testDOMText() {
        let dom = DOMText(html: """
        <!DOCTYPE html><html><head><title>Report</title>
        <style>p::before { content: "Hidden style text"; }</style>
        <script>var q = "What is hidden in a script?";</script></head>
        <body><!-- What is in a comment? -->
        <h2>Research question</h2>
        <p>What&nbsp;are the <em>effects</em> of
           remote work on citizens&#8217; trust &amp; productivity?</p>
        <div>Line one</div><div>Line two</div>
        <input type="search" value="Can &quot;LLMs&quot; screen abstracts?">
        <button>Show all 1,234 references</button>
        </body></html>
        """)
        XCTAssertTrue(dom.contains("What are the effects of remote work on citizens\u{2019} trust & productivity?"))
        XCTAssertTrue(dom.contains("What are the effects of\nremote work"))
        XCTAssertFalse(dom.contains("what are the effects"), "matching is case-sensitive")
        XCTAssertFalse(dom.contains("What is hidden in a script?"))
        XCTAssertFalse(dom.contains("Hidden style text"))
        XCTAssertFalse(dom.contains("What is in a comment?"))
        XCTAssertTrue(dom.contains("Line one Line two"), "a tag can separate words")
        XCTAssertTrue(dom.contains("Can \"LLMs\" screen abstracts?"), "form field values count")
        XCTAssertTrue(dom.showsAll(1234))
        XCTAssertFalse(dom.showsAll(123))
        XCTAssertFalse(dom.contains(""))

        XCTAssertTrue(DOMText(html: "<a>Show all 1234 references</a>").showsAll(1234))
        XCTAssertTrue(DOMText(html: "<a>Show all 1 reference</a>").showsAll(1))
        XCTAssertTrue(DOMText(html: "<a>Show all 1 references</a>").showsAll(1))
        XCTAssertEqual(DOMText.decodeEntities("&lt;b&gt; &#x27;x&#39; &unknown; & done"), "<b> 'x' &unknown; & done")
    }

    // MARK: In the scan

    private func workspace(config: String?) throws -> TempFolder {
        let ws = try TempFolder()
        if let config { try ws.write("workspace.yml", config) }
        // DC-1: the DOM shows the question and the right count.
        try writeSingleTest(ws, "DC-1", question: "What is known about X?", references: 3, skip: ["dom"])
        try ws.write("DC-1/DC-1_report_DOM.html",
                     "<h1>What is known <b>about</b> X?</h1><button>Show all 3 references</button>")
        // DC-2: variant 1 passes; variant 2's DOM rewords the question and shows the wrong count.
        try writeVariant(ws, "DC-2", 1, question: "First?", references: 2, skip: ["dom"])
        try ws.write("DC-2/DC-2_variant1_report_DOM.html", "<p>First?</p><p>Show all 2 references</p>")
        try writeVariant(ws, "DC-2", 2, question: "Second question?", references: 5, skip: ["dom"])
        try ws.write("DC-2/DC-2_variant2_report_DOM.html", "<p>Second query?</p><p>Show all 4 references</p>")
        // DC-3: no DOM at all (an error already), so nothing to check.
        try writeSingleTest(ws, "DC-3", skip: ["dom"])
        return ws
    }

    func testChecksRunWhenTurnedOn() throws {
        let ws = try workspace(config: "dom_checks:\n  rq_text_string_check: True\n  all_n_references_check: True\n")
        let scan = try WorkspaceScanner.scan(ws.url)
        XCTAssertFalse(scan.otherItems.contains("workspace.yml"))
        XCTAssertTrue(scan.config.rqTextStringCheck && scan.config.allNReferencesCheck)
        XCTAssertEqual(scan.config.fileName, "workspace.yml")

        let one = try XCTUnwrap(scan.test("DC-1"))
        XCTAssertEqual(one.status, .complete, one.messages.joined(separator: "\n"))
        XCTAssertEqual(one.questions[0].domChecks, [
            DOMCheckResult(kind: .questionText, passed: true),
            DOMCheckResult(kind: .showAllReferences(3), passed: true),
        ])

        let two = try XCTUnwrap(scan.test("DC-2"))
        XCTAssertEqual(two.status, .warnings)
        XCTAssertEqual(two.rowStatus(two.questions[0]), .complete)
        XCTAssertEqual(two.questions[1].domChecks.map(\.passed), [false, false])
        XCTAssertTrue(two.hasIssue(.warning, containing:
            "DC-2_variant2_report_DOM.html: the research question\u{2019}s exact text doesn\u{2019}t appear in the report DOM"))
        XCTAssertTrue(two.hasIssue(.warning, containing:
            "DC-2_variant2_report_DOM.html: \u{201C}Show all 5 references\u{201D} doesn\u{2019}t appear in the report DOM"))

        let three = try XCTUnwrap(scan.test("DC-3"))
        XCTAssertTrue(three.questions[0].domChecks.isEmpty)
        XCTAssertFalse(three.messages.contains { $0.contains("doesn\u{2019}t appear") })
    }

    func testOnlyTheChecksTurnedOnRun() throws {
        let ws = try workspace(config: "dom_checks:\n  all_n_references_check: True\n")
        let two = try XCTUnwrap(try WorkspaceScanner.scan(ws.url).test("DC-2"))
        XCTAssertEqual(two.questions[1].domChecks, [DOMCheckResult(kind: .showAllReferences(5), passed: false)])
        XCTAssertFalse(two.messages.contains { $0.contains("exact text") })
    }

    func testNoConfigNoChecks() throws {
        let ws = try workspace(config: nil)
        let scan = try WorkspaceScanner.scan(ws.url)
        XCTAssertFalse(scan.config.anyDOMCheck)
        XCTAssertNil(scan.config.fileName)
        XCTAssertEqual(scan.test("DC-2")?.status, .complete)
        XCTAssertTrue(scan.tests.allSatisfy { $0.questions.allSatisfy { $0.domChecks.isEmpty } })
    }

    func testConfigProblemsAreReported() throws {
        let ws = try workspace(config: "dom_checks:\n  rq_text_string_check: perhaps\n")
        let scan = try WorkspaceScanner.scan(ws.url)
        XCTAssertFalse(scan.config.anyDOMCheck)
        XCTAssertEqual(scan.config.problems.count, 1)
    }
}
