import Foundation

/// The two export formats: a CSV sheet (one row per research question) and
/// a self-contained single-page HTML report (docs/FILE_FORMAT.md §4).
public enum Exporter {
    // MARK: - CSV

    public static let csvColumns = [
        "Test ID", "Type", "Variant", "Research Question", "References Found",
        "References in File Name", "Count Matches", "Status", "Issues", "Citation Key Clashes",
        "Annotation", "Ground Truth (APA 7)", "Ground Truth DOI",
    ]

    /// RFC 4180 CSV: a header row, then one row per research question, CRLF
    /// line endings, fields quoted only when they need it. Test-level issues
    /// are repeated on every row of their test, so a row read on its own
    /// still tells the whole story. Clashing citation keys are listed in
    /// their own column, not as issues; the ground truth (a test-level
    /// item) is repeated on every row of its test, like test-level issues.
    public static func csv(_ tests: [TestRun]) -> String {
        var lines = [csvLine(csvColumns)]
        for test in tests {
            for question in test.questions {
                let issues = (test.issues + question.issues).map { issue in
                    (issue.severity == .error ? "Error: " : "Warning: ") + issue.message
                }
                lines.append(csvLine([
                    test.id,
                    test.kind.title,
                    question.variant.map(String.init) ?? "",
                    question.question ?? "",
                    question.referencesFound.map(String.init) ?? "",
                    question.referencesInFileName.map(String.init) ?? "",
                    question.countMatches.map { $0 ? "Yes" : "No" } ?? "",
                    test.rowStatus(question).title,
                    issues.joined(separator: "; "),
                    question.keyClashes.map(\.description).joined(separator: "; "),
                    question.annotation ?? "",
                    test.groundTruth?.reference?.plain ?? "",
                    test.groundTruth?.doi ?? "",
                ]))
            }
        }
        return lines.map { $0 + "\r\n" }.joined()
    }

    /// The CSV as UTF-8 with a byte-order mark, so Excel and Numbers detect
    /// the encoding (research questions often contain curly quotes and
    /// accented letters).
    public static func csvData(_ tests: [TestRun]) -> Data {
        Data(("\u{FEFF}" + csv(tests)).utf8)
    }

    static func csvLine(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - HTML

    /// A single HTML page with its styles inline and no scripts or external
    /// resources, so it can be e-mailed, archived or printed as it is.
    public static func html(_ tests: [TestRun], workspaceName: String, generated: Date,
                            timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let when = formatter.string(from: generated)

        let complete = tests.filter { $0.status == .complete }.count
        let warnings = tests.filter { $0.status == .warnings }.count
        let errors = tests.filter { $0.status == .errors }.count
        let questions = tests.reduce(0) { $0 + $1.questions.count }
        let references = tests.reduce(0) { $0 + $1.totalReferences }

        var body = ""
        body += "<header>\n"
        body += "<h1>Literature review test runs</h1>\n"
        body += "<p class=\"meta\">Workspace <strong>\(escape(workspaceName))</strong>, exported \(escape(when))</p>\n"
        body += "</header>\n"

        body += "<section class=\"summary\" aria-label=\"Summary\">\n"
        if !tests.isEmpty {
            body += "<div class=\"bar\" role=\"img\" aria-label=\"\(complete) complete, \(warnings) with warnings, \(errors) with errors\">"
            let segments: [(count: Int, status: Status)] = [(complete, .complete), (warnings, .warnings), (errors, .errors)]
            for (count, status) in segments where count > 0 {
                body += "<span class=\"\(cssClass(status))\" style=\"flex-grow: \(count)\"></span>"
            }
            body += "</div>\n"
        }
        body += "<p>\(TextSupport.plural(tests.count, "test")): "
        body += "<span class=\"key complete\">\(complete) complete</span>, "
        body += "<span class=\"key warnings\">\(warnings) with warnings</span>, "
        body += "<span class=\"key errors\">\(errors) with errors</span>. "
        body += "\(TextSupport.plural(questions, "research question")) and "
        body += "\(grouped(references)) \(references == 1 ? "reference" : "references") found.</p>\n"
        body += "</section>\n"

        if tests.isEmpty {
            body += "<p class=\"empty\">This workspace has no tests yet.</p>\n"
        } else {
            body += "<table>\n<thead><tr>"
            body += "<th scope=\"col\">Test</th><th scope=\"col\">Type</th><th scope=\"col\">Variant</th>"
            body += "<th scope=\"col\">Research question</th><th scope=\"col\" class=\"num\">Found</th>"
            body += "<th scope=\"col\" class=\"num\">In file name</th><th scope=\"col\">Status</th>"
            body += "</tr></thead>\n"
            for test in tests {
                body += testRows(test)
            }
            body += "</table>\n"
        }
        body += "<footer>Exported by QDVC Auto Lit Review Tester. References are counted as BibTeX entries, "
        body += "not counting @string, @preamble and @comment. Key clashes (citation keys shared by separate "
        body += "entries) are listed for information and don\u{2019}t affect the status.</footer>\n"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(workspaceName)) \u{2013} literature review test runs</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        <main>
        \(body)</main>
        </body>
        </html>

        """
    }

    private static func testRows(_ test: TestRun) -> String {
        let allIssues = test.issues + test.questions.flatMap(\.issues)
        let hasClashes = test.questions.contains { !$0.keyClashes.isEmpty }
        let hasNotes = !allIssues.isEmpty || hasClashes || test.groundTruth?.reference != nil
        let span = test.questions.count + (hasNotes ? 1 : 0)
        var html = "<tbody class=\"test\">\n"
        if test.questions.isEmpty {
            html += "<tr><th scope=\"rowgroup\" class=\"id\"\(span > 1 ? " rowspan=\"2\"" : "")>\(escape(test.id))</th>"
            html += "<td>\(escape(test.kind.title))</td><td colspan=\"4\" class=\"none\">No research questions found</td>"
            html += "<td>\(statusCell(test.status))</td></tr>\n"
        }
        for (index, question) in test.questions.enumerated() {
            html += "<tr>"
            if index == 0 {
                html += "<th scope=\"rowgroup\" class=\"id\"\(span > 1 ? " rowspan=\"\(span)\"" : "")>\(escape(test.id))</th>"
            }
            html += "<td class=\"type\">\(index == 0 ? escape(test.kind.title) : "")</td>"
            html += "<td class=\"variant\">\(question.variant.map(String.init) ?? "\u{2013}")</td>"
            let note = question.annotation.map { "<p class=\"note\">\(escape($0))</p>" } ?? ""
            if let text = question.question {
                html += "<td class=\"rq\">\(escape(text))\(note)</td>"
            } else {
                html += "<td class=\"rq\"><span class=\"none\">Research question not available</span>\(note)</td>"
            }
            html += "<td class=\"num\">\(question.referencesFound.map(grouped) ?? "\u{2013}")</td>"
            let mismatch = question.countMatches == false
            html += "<td class=\"num\(mismatch ? " mismatch" : "")\">"
            html += question.referencesInFileName.map(grouped) ?? "\u{2013}"
            if mismatch { html += "<span class=\"visually-hidden\"> (does not match)</span>" }
            html += "</td>"
            html += "<td>\(statusCell(test.rowStatus(question)))</td>"
            html += "</tr>\n"
        }
        if hasNotes {
            html += "<tr class=\"issues\"><td colspan=\"6\"><ul>"
            if let reference = test.groundTruth?.reference {
                html += "<li class=\"truth\"><span class=\"sev\">Ground truth</span> \(reference.html)</li>"
            }
            for issue in test.issues {
                html += issueItem(issue, scope: nil)
            }
            for question in test.questions {
                for issue in question.issues {
                    html += issueItem(issue, scope: question.variant.map { "Variant \($0)" })
                }
            }
            for question in test.questions {
                for clash in question.keyClashes {
                    let scope = question.variant.map { "Variant \($0): " } ?? ""
                    html += "<li class=\"info\"><span class=\"sev\">Key clash</span> "
                        + escape(scope + clash.description) + "</li>"
                }
            }
            html += "</ul></td></tr>\n"
        }
        html += "</tbody>\n"
        return html
    }

    private static func issueItem(_ issue: Issue, scope: String?) -> String {
        let word = issue.severity == .error ? "Error" : "Warning"
        let prefix = scope.map { "\(escape($0)): " } ?? ""
        return "<li class=\"\(issue.severity == .error ? "errors" : "warnings")\"><span class=\"sev\">\(word)</span> "
            + prefix + escape(issue.message) + "</li>"
    }

    private static func statusCell(_ status: Status) -> String {
        "<span class=\"status \(cssClass(status))\">\(status.title)</span>"
    }

    private static func cssClass(_ status: Status) -> String {
        switch status {
        case .complete: return "complete"
        case .warnings: return "warnings"
        case .errors: return "errors"
        }
    }

    /// Escapes text for HTML element content and attribute values.
    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    /// 1532 → "1,532".
    static func grouped(_ number: Int) -> String {
        let digits = String(number.magnitude)
        var out = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out += "," }
            out.append(character)
        }
        return (number < 0 ? "-" : "") + out
    }

    private static let stylesheet = """
    :root {
      --ink: #1C2430; --muted: #5D6775; --rule: #D6DBE1; --page: #EEF1F4; --paper: #FFFFFF;
      --complete: #1F7A4D; --warnings: #A15C00; --errors: #B42318; --tint: #F6F8FA;
      --sans: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "Segoe UI", Arial, sans-serif;
      --serif: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
    }
    @media (prefers-color-scheme: dark) {
      :root { --ink: #E6EAF0; --muted: #A3ACB9; --rule: #3A424D; --page: #161A20; --paper: #1E232A;
              --complete: #4CC38A; --warnings: #F0A840; --errors: #FF7A6E; --tint: #252B33; }
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--page); color: var(--ink); font: 15px/1.45 var(--sans); }
    main { max-width: 1120px; margin: 32px auto; padding: 36px 40px 28px; background: var(--paper);
           border-radius: 10px; box-shadow: 0 1px 2px rgba(20, 30, 45, 0.08); }
    h1 { font-size: 26px; line-height: 1.2; font-weight: 650; margin: 0 0 4px; letter-spacing: -0.01em; }
    .meta { margin: 0; color: var(--muted); }
    .meta strong { color: var(--ink); font-weight: 600; }
    .summary { margin: 28px 0 24px; }
    .summary p { margin: 10px 0 0; max-width: 72ch; }
    .bar { display: flex; gap: 3px; height: 14px; border-radius: 7px; overflow: hidden; }
    .bar span { display: block; min-width: 6px; }
    .bar .complete { background: var(--complete); }
    .bar .warnings { background: var(--warnings); }
    .bar .errors { background: var(--errors); }
    .key { font-weight: 600; }
    .key.complete { color: var(--complete); }
    .key.warnings { color: var(--warnings); }
    .key.errors { color: var(--errors); }
    table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
    thead th { position: sticky; top: 0; background: var(--paper); text-align: left; font-weight: 600;
               color: var(--muted); font-size: 13px; padding: 8px 10px; border-bottom: 2px solid var(--ink); }
    tbody.test { border-bottom: 1px solid var(--rule); }
    td, tbody th { padding: 9px 10px; vertical-align: top; text-align: left; }
    tbody th.id { font-weight: 650; white-space: nowrap; }
    td.type, td.variant { color: var(--muted); white-space: nowrap; }
    td.rq { font-family: var(--serif); font-size: 16px; line-height: 1.5; max-width: 60ch; }
    td.none, td.rq.none { color: var(--muted); font-style: italic; font-family: var(--sans); font-size: 14px; }
    .num { text-align: right; white-space: nowrap; }
    td.mismatch { color: var(--errors); font-weight: 650; }
    td.mismatch::before { content: "\\2260\\00a0"; }
    .status { white-space: nowrap; font-weight: 600; }
    .status::before { content: ""; display: inline-block; width: 9px; height: 9px; border-radius: 50%;
                      margin-right: 7px; vertical-align: 1px; background: currentColor; }
    .status.complete { color: var(--complete); }
    .status.warnings { color: var(--warnings); }
    .status.errors { color: var(--errors); }
    tr.issues td { padding-top: 0; padding-bottom: 12px; }
    tr.issues ul { margin: 0; padding: 8px 12px; list-style: none; background: var(--tint); border-radius: 6px;
                   font-size: 13px; }
    tr.issues li { padding: 2px 0; overflow-wrap: anywhere; }
    tr.issues .sev { font-weight: 650; }
    tr.issues li.errors .sev { color: var(--errors); }
    tr.issues li.warnings .sev { color: var(--warnings); }
    tr.issues li.info .sev { color: var(--muted); }
    tr.issues li.truth { font-family: var(--serif); font-size: 14px; padding-bottom: 4px; }
    tr.issues li.truth .sev { font-family: var(--sans); font-size: 13px; color: var(--ink); }
    td.rq .note { margin: 6px 0 0; padding-left: 10px; border-left: 3px solid var(--rule); font-family: var(--sans);
                  font-size: 13px; line-height: 1.45; color: var(--muted); white-space: pre-line; }
    td.rq .none { color: var(--muted); font-style: italic; font-family: var(--sans); font-size: 14px; }
    .empty { color: var(--muted); }
    footer { margin-top: 24px; color: var(--muted); font-size: 12px; }
    .visually-hidden { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
    @media (max-width: 720px) {
      main { margin: 0; padding: 20px 16px; border-radius: 0; }
      td.type, thead th:nth-child(2) { display: none; }
    }
    @media print {
      body { background: #FFFFFF; font-size: 11pt; }
      main { margin: 0; padding: 0; box-shadow: none; max-width: none; }
      thead { display: table-header-group; }
      thead th { position: static; }
      tbody.test { break-inside: avoid; }
      .bar span { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    }
    """
}
