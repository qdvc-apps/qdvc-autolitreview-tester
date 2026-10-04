import Foundation

extension Exporter {
    /// GitHub-flavoured Markdown, for reading on GitHub, GitLab and the like:
    /// a summary, an overview table whose test IDs link to a section per
    /// test, and in each section the ground truth, a table of research
    /// questions with their annotations, links to the files, the issues and
    /// key clashes. Status is shown
    /// with an emoji and a word, so it reads without colour. Text from the
    /// workspace is escaped, so it can never turn into Markdown or HTML.
    ///
    /// With `linkBase` (the folder the Markdown file is saved in, usually the
    /// workspace itself, as README.md), each test's section links to its
    /// folder and to every artifact found, by relative paths, so the links
    /// work on GitHub and in a local clone alike.
    public static func markdown(_ tests: [TestRun], workspaceName: String, generated: Date,
                                timeZone: TimeZone = .current, linkBase: URL? = nil) -> String {
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
            md += "\(cell(ExportDate.shortRange(test.exportDates) ?? "\u{2013}")) | \(cell(test.groundTruth?.shortCitation ?? "")) | "
            md += "\(statusText(test.status)) |\n"
        }
        md += "\n"

        for test in tests {
            md += section(test, linkBase: linkBase)
        }
        md += "---\n\n"
        md += "Exported by QDVC Auto Lit Review Tester. References are counted as BibTeX entries, not counting "
        md += "`@string`, `@preamble` and `@comment`. Key clashes (citation keys shared by separate entries) are "
        md += "listed for information and don\u{2019}t affect the status.\n"
        return md
    }

    private static func section(_ test: TestRun, linkBase: URL?) -> String {
        var md = "## \(inline(test.id))\n\n"
        var facts = [statusText(test.status), test.kind.title,
                     TextSupport.plural(test.totalReferences, "reference")]
        if let date = ExportDate.shortRange(test.exportDates) { facts.append("exported \(date)") }
        md += facts.joined(separator: ", ") + "\n\n"

        if let base = linkBase {
            let folder = relativeLink(from: base, to: test.folder) + "/"
            md += "**Folder:** [\(inline(test.id))/](\(folder))\n\n"
        }

        if let truth = test.groundTruth, let reference = truth.reference {
            md += "**Ground truth:** \(markdown(reference))"
            if let base = linkBase, let url = truth.url {
                md += " ([BibTeX](\(relativeLink(from: base, to: url))))"
            }
            md += "\n\n"
        }

        // The research questions with their reference counts and the
        // tester's annotations. (A count that doesn't match the file name
        // is listed under Issues.)
        let multi = test.kind == .multi
        md += multi ? "| Variant | Research question | Found | Annotation |\n"
                    : "| Research question | Found | Annotation |\n"
        md += multi ? "| ---: | --- | ---: | --- |\n" : "| --- | ---: | --- |\n"
        for question in test.questions {
            var row = "| "
            if multi { row += "\(question.variant.map(String.init) ?? "\u{2013}") | " }
            row += question.question.map(cell) ?? "*Research question not available*"
            row += " | \(question.referencesFound.map(grouped) ?? "\u{2013}") | "
            row += question.annotation.map(cell) ?? noAnnotation
            row += " |\n"
            md += row
        }
        md += "\n"

        if let base = linkBase {
            md += filesList(test, base: base)
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

    /// What the Annotation column says when there is none.
    static let noAnnotation = "_(No annotation found.)_"

    /// The artifacts linked under each test's table, in the standard order.
    /// The research question and annotation files aren't linked: their text
    /// is already in the table.
    static let linkedArtifacts: [ArtifactKind] = [.queryAsked, .responseReceived, .references, .report, .reportDOM]

    /// The link text for an artifact.
    static func linkText(_ kind: ArtifactKind) -> String {
        kind == .references ? "references BIB" : kind.noun
    }

    /// Links to each research question's artifacts; missing ones are left
    /// out (they are listed under Issues).
    private static func filesList(_ test: TestRun, base: URL) -> String {
        func links(_ question: ResearchQuestion) -> String {
            linkedArtifacts.compactMap { kind -> String? in
                guard let file = question.file(kind) else { return nil }
                return "[\(inline(linkText(kind)))](\(relativeLink(from: base, to: file.url)))"
            }.joined(separator: ", ")
        }
        if test.kind == .single, let question = test.questions.first {
            let list = links(question)
            return list.isEmpty ? "" : "**Files:** \(list)\n\n"
        }
        let lines = test.questions.compactMap { question -> String? in
            let list = links(question)
            return list.isEmpty ? nil : "- Variant \(question.variant.map(String.init) ?? "?"): \(list)\n"
        }
        return lines.isEmpty ? "" : "**Files**\n\n" + lines.joined() + "\n"
    }

    /// The path from the folder `base` to `target`, with `..` where needed,
    /// each part percent-encoded (spaces, parentheses and the like), for a
    /// Markdown link.
    public static func relativeLink(from base: URL, to target: URL) -> String {
        let from = base.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let to = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] { common += 1 }
        let parts = Array(repeating: "..", count: from.count - common) + to[common...]
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/()[]<> ")
        return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
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

    /// For inline code: backticks can't be escaped inside it, so they become
    /// a look-alike.
    static func code(_ text: String) -> String {
        text.replacingOccurrences(of: "`", with: "\u{2018}")
    }
}
