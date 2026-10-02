import Foundation

extension Exporter {
    /// GitHub-flavoured Markdown, for reading on GitHub, GitLab and the like:
    /// a summary, an overview table whose test IDs link to a section per
    /// test, and in each section the ground truth, a table of research
    /// questions, the annotations, issues and key clashes. Status is shown
    /// with an emoji and a word, so it reads without colour. Text from the
    /// workspace is escaped, so it can never turn into Markdown or HTML.
    public static func markdown(_ tests: [TestRun], workspaceName: String, generated: Date,
                                timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let complete = tests.filter { $0.status == .complete }.count
        let warnings = tests.filter { $0.status == .warnings }.count
        let errors = tests.filter { $0.status == .errors }.count
        let questions = tests.reduce(0) { $0 + $1.questions.count }
        let references = tests.reduce(0) { $0 + $1.totalReferences }

        var md = "# Literature review test runs\n\n"
        md += "Workspace **\(inline(workspaceName))**, exported \(formatter.string(from: generated)).\n\n"
        md += "**\(TextSupport.plural(tests.count, "test"))**: \(complete) complete, \(warnings) with warnings, "
        md += "\(errors) with errors. \(TextSupport.plural(questions, "research question")) and "
        md += "\(grouped(references)) \(references == 1 ? "reference" : "references") found.\n\n"

        guard !tests.isEmpty else {
            return md + "This workspace has no tests yet.\n"
        }

        // Overview
        md += "| Test | Type | RQs | References | Export date | Ground truth | Status |\n"
        md += "| --- | --- | ---: | ---: | --- | --- | --- |\n"
        for test in tests {
            let refs = test.questions.map { $0.referencesFound.map(grouped) ?? "\u{2013}" }.joined(separator: ", ")
            md += "| [\(inline(test.id))](#\(anchor(test.id))) | \(test.kind.title) | \(test.questions.count) | \(refs) | "
            md += "\(cell(test.dateText ?? "\u{2013}")) | \(cell(test.groundTruth?.shortCitation ?? "")) | "
            md += "\(statusText(test.status)) |\n"
        }
        md += "\n"

        for test in tests {
            md += section(test)
        }
        md += "---\n\n"
        md += "Exported by QDVC Auto Lit Review Tester. References are counted as BibTeX entries, not counting "
        md += "`@string`, `@preamble` and `@comment`. Key clashes (citation keys shared by separate entries) are "
        md += "listed for information and don\u{2019}t affect the status.\n"
        return md
    }

    private static func section(_ test: TestRun) -> String {
        var md = "## \(inline(test.id))\n\n"
        var facts = [statusText(test.status), test.kind.title,
                     TextSupport.plural(test.totalReferences, "reference")]
        if let date = test.dateText { facts.append("exported \(date)") }
        md += facts.joined(separator: ", ") + "\n\n"

        if let reference = test.groundTruth?.reference {
            md += "**Ground truth:** \(markdown(reference))\n\n"
        }

        let multi = test.kind == .multi
        md += multi ? "| Variant | Research question | Found | In file name | Export date |\n"
                    : "| Research question | Found | In file name | Export date |\n"
        md += multi ? "| ---: | --- | ---: | ---: | --- |\n" : "| --- | ---: | ---: | --- |\n"
        for question in test.questions {
            var row = "| "
            if multi { row += "\(question.variant.map(String.init) ?? "\u{2013}") | " }
            row += question.question.map(cell) ?? "*Research question not available*"
            row += " | \(question.referencesFound.map(grouped) ?? "\u{2013}") | "
            if let named = question.referencesInFileName {
                row += question.countMatches == false ? "**\(grouped(named))** \u{2260}" : grouped(named)
            } else {
                row += "\u{2013}"
            }
            row += " | \(cell(ExportDate.longRange(question.exportDates) ?? "\u{2013}")) |\n"
            md += row
        }
        md += "\n"

        let annotated = test.questions.filter { $0.annotation != nil }
        if !annotated.isEmpty {
            md += "**Annotations**\n\n"
            for question in annotated {
                let scope = question.variant.map { "Variant \($0): " } ?? ""
                md += "- \(scope)\(paragraph(question.annotation ?? ""))\n"
            }
            md += "\n"
        }

        let issues = test.issues.map { ($0, nil as Int?) }
            + test.questions.flatMap { question in question.issues.map { ($0, question.variant) } }
        if !issues.isEmpty {
            md += "**Issues**\n\n"
            for (issue, variant) in issues {
                let label = issue.severity == .error ? "\u{274C} **Error:**" : "\u{26A0}\u{FE0F} **Warning:**"
                let scope = variant.map { "Variant \($0): " } ?? ""
                md += "- \(label) \(scope)\(inline(issue.message))\n"
            }
            md += "\n"
        }

        let clashes = test.questions.flatMap { question in question.keyClashes.map { ($0, question.variant) } }
        if !clashes.isEmpty {
            md += "**Key clashes** (for information)\n\n"
            for (clash, variant) in clashes {
                let scope = variant.map { "Variant \($0): " } ?? ""
                let list = TextSupport.list(clash.occurrences.map { "`\(code($0.key))` (line \($0.line))" })
                md += "- \(scope)\(list)\n"
            }
            md += "\n"
        }
        return md
    }

    private static func statusText(_ status: Status) -> String {
        switch status {
        case .complete: return "\u{2705} Complete"
        case .warnings: return "\u{26A0}\u{FE0F} Warnings"
        case .errors: return "\u{274C} Errors"
        }
    }

    /// The reference with its italics as `*…*`.
    static func markdown(_ reference: FormattedReference) -> String {
        reference.segments.map { segment in
            let text = inline(segment.text)
            guard segment.italic else { return text }
            // Keep spaces outside the asterisks, or Markdown won't italicise.
            let core = text.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return text }
            let lead = text.prefix { $0 == " " }, trail = String(text.reversed().prefix { $0 == " " })
            return "\(lead)*\(core)*\(trail)"
        }.joined()
    }

    /// GitHub's heading anchor for a test ID (A–Z, 0–9 and dashes): lowercase.
    static func anchor(_ id: String) -> String { id.lowercased() }

    /// Escapes the characters Markdown (and inline HTML) would act on, and
    /// joins lines with spaces.
    static func inline(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\\", "`", "*", "_", "[", "]", "<", ">", "|", "~", "#":
                out.append("\\")
                out.append(character)
            case "&":
                out += "&amp;"
            default:
                out.append(character.isNewline ? " " : character)
            }
        }
        return out
    }

    /// For a table cell: escaped, with line breaks kept as `<br>`.
    static func cell(_ text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { inline(String($0)) }.joined(separator: "<br>")
    }

    /// For a list item: escaped, with line breaks kept (two spaces, newline,
    /// indent), so a multi-line annotation stays inside its bullet.
    static func paragraph(_ text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { inline(String($0)) }.joined(separator: "  \n  ")
    }

    /// For inline code: backticks can't be escaped inside it, so they become
    /// a look-alike.
    static func code(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "\u{2018}")
    }
}
