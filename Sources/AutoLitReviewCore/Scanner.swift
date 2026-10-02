import Foundation

/// Reads a workspace folder and checks every test in it (docs/FILE_FORMAT.md
/// §3 lists the checks). Scanning only reads; it never changes a file.
public enum WorkspaceScanner {
    /// Scans the workspace. Throws only when the workspace folder itself
    /// can't be listed; problems inside tests are reported as issues.
    public static func scan(_ root: URL, fileManager: FileManager = .default) throws -> WorkspaceScan {
        let entries = try listing(root, fileManager: fileManager)
        var tests: [TestRun] = []
        var other: [String] = []
        for entry in entries {
            if entry.isDirectory, Naming.isValidTestID(entry.name) {
                tests.append(scanTest(at: entry.url, fileManager: fileManager))
            } else {
                other.append(entry.name)
            }
        }
        return WorkspaceScan(root: root, tests: tests, otherItems: other)
    }

    /// Scans one test folder. Its name is taken as the test ID.
    public static func scanTest(at folder: URL, fileManager: FileManager = .default) -> TestRun {
        var scanner = TestScanner(id: folder.lastPathComponent, folder: folder, fileManager: fileManager)
        return scanner.run()
    }

    // MARK: - Listing

    struct Entry {
        let url: URL
        let name: String
        let isDirectory: Bool
        let size: Int64?
    }

    /// The visible items of a folder in natural order. Hidden items (such as
    /// .DS_Store, or a test that is still being created) are skipped.
    static func listing(_ folder: URL, fileManager: FileManager) throws -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let urls = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                       options: [.skipsHiddenFiles])
        return urls.compactMap { url -> Entry? in
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Entry(url: url, name: name, isDirectory: values?.isDirectory ?? false,
                         size: values?.fileSize.map { Int64($0) })
        }
        .sorted { Naming.naturalLess($0.name, $1.name) }
    }

    // MARK: - Names

    /// An item name in a test folder after its `ID_` prefix, split into the
    /// variant (if the name has one) and what follows it.
    struct ParsedName: Equatable {
        var variant: Int?
        /// The variant was written `query_variantN` rather than `variantN`.
        var queryPrefix = false
        /// The variant number has no leading zeros.
        var plainDigits = true
        /// The rest of the name, after `variantN_` (or the whole name after
        /// `ID_` when there is no variant).
        var rest: String
    }

    /// Splits `name` for the test `testID`; nil when the name doesn't start
    /// with `testID_`.
    static func parse(_ name: String, testID: String) -> ParsedName? {
        let prefix = testID + "_"
        guard name.hasPrefix(prefix) else { return nil }
        let body = String(name.dropFirst(prefix.count))
        var tail = Substring(body)
        var queryPrefix = false
        if tail.hasPrefix("query_variant") {
            queryPrefix = true
            tail = tail.dropFirst("query_".count)
        }
        if tail.hasPrefix("variant") {
            let afterWord = tail.dropFirst("variant".count)
            let digits = afterWord.prefix { $0.isASCII && $0.isNumber }
            let afterDigits = afterWord.dropFirst(digits.count)
            if !digits.isEmpty, let number = Int(digits), afterDigits.isEmpty || afterDigits.hasPrefix("_") {
                return ParsedName(variant: number, queryPrefix: queryPrefix,
                                  plainDigits: String(number) == String(digits),
                                  rest: String(afterDigits.isEmpty ? afterDigits : afterDigits.dropFirst()))
            }
        }
        return ParsedName(variant: nil, rest: body)
    }

    /// The artifacts kept in a query folder, by name after the prefix.
    static let queryFolderKinds: [String: ArtifactKind] = [
        ArtifactKind.queryAsked.nameSuffix(): .queryAsked,
        ArtifactKind.responseReceived.nameSuffix(): .responseReceived,
        ArtifactKind.rqText.nameSuffix(): .rqText,
    ]

    /// A top-level artifact name after the prefix: `references_n67.bib`,
    /// `report.pdf` or `report_DOM.html`. For references, `count` is the
    /// number in the name, or nil when it has none (`references.bib`) or it
    /// isn't a number.
    static func parseTopLevel(_ rest: String) -> (kind: ArtifactKind, count: Int?)? {
        if rest == ArtifactKind.report.nameSuffix() { return (.report, nil) }
        if rest == ArtifactKind.reportDOM.nameSuffix() { return (.reportDOM, nil) }
        guard rest.hasPrefix("references"), rest.hasSuffix(".bib"), rest.count >= "references.bib".count else {
            return nil
        }
        let middle = rest.dropFirst("references".count).dropLast(".bib".count)
        guard middle.hasPrefix("_n") else { return (.references, nil) }
        let digits = middle.dropFirst(2)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return (.references, nil) }
        return (.references, Int(digits))
    }
}

/// The state of one test folder's scan.
private struct TestScanner {
    struct Candidate {
        let file: ArtifactFile
        /// Path relative to the test folder, for messages.
        let relativePath: String
        let canonical: Bool
        /// For references: the count in the file name.
        let countInName: Int?
    }

    let id: String
    let folder: URL
    let fileManager: FileManager

    /// Candidates by variant (nil for single-RQ items) and kind.
    var found: [Int?: [ArtifactKind: [Candidate]]] = [:]
    /// Every variant (or nil) that has a query folder or an artifact.
    var slots = Set<Int?>()
    /// Names of the single-RQ items (for the "mixed" warning).
    var singleItems: [String] = []
    var testIssues: [Issue] = []
    /// The optional ground truth and annotations (docs/FILE_FORMAT.md §2.5).
    var groundTruth: GroundTruth?
    var annotations: [Int?: (url: URL, text: String)] = [:]

    init(id: String, folder: URL, fileManager: FileManager) {
        self.id = id
        self.folder = folder
        self.fileManager = fileManager
    }

    mutating func run() -> TestRun {
        let entries: [WorkspaceScanner.Entry]
        do {
            entries = try WorkspaceScanner.listing(folder, fileManager: fileManager)
        } catch {
            return TestRun(id: id, folder: folder, kind: .single, questions: [],
                           issues: [.error("Couldn\u{2019}t read the test folder: \(error.localizedDescription)")])
        }

        for entry in entries {
            guard let parsed = WorkspaceScanner.parse(entry.name, testID: id) else {
                testIssues.append(.warning("Unrecognised item: \(entry.name)"))
                continue
            }
            if entry.isDirectory {
                scanFolderEntry(entry, parsed)
            } else {
                scanFileEntry(entry, parsed)
            }
        }

        let variants = slots.compactMap { $0 }.sorted()
        let kind: TestKind = variants.isEmpty ? .single : .multi
        if kind == .multi {
            checkVariantNumbering(variants)
            if !singleItems.isEmpty {
                testIssues.append(.warning("This test has variants, but also single-RQ items: "
                                           + TextSupport.list(singleItems)))
            }
        }
        let questionSlots: [Int?] = kind == .single ? [nil] : variants.map { Optional($0) }
        let questions = questionSlots.map { buildQuestion($0) }
        return TestRun(id: id, folder: folder, kind: kind, questions: questions, issues: testIssues,
                       groundTruth: groundTruth)
    }

    // MARK: Entries

    private mutating func scanFolderEntry(_ entry: WorkspaceScanner.Entry, _ parsed: WorkspaceScanner.ParsedName) {
        if parsed.variant == nil, parsed.rest == "query" {
            singleItems.append(entry.name + "/")
            scanQueryFolder(entry, variant: nil)
        } else if let variant = parsed.variant, parsed.rest.isEmpty {
            if !(parsed.queryPrefix && parsed.plainDigits) {
                let expected = Naming.queryFolderName(testID: id, variant: variant)
                testIssues.append(.warning("Folder \(entry.name) doesn\u{2019}t follow the naming convention; expected \(expected)"))
            }
            scanQueryFolder(entry, variant: variant)
        } else {
            testIssues.append(.warning("Unrecognised folder: \(entry.name)"))
        }
    }

    private mutating func scanFileEntry(_ entry: WorkspaceScanner.Entry, _ parsed: WorkspaceScanner.ParsedName) {
        if parsed.variant == nil, parsed.rest == "ground_truth.bib" {
            readGroundTruth(entry)
            return
        }
        if let top = WorkspaceScanner.parseTopLevel(parsed.rest) {
            let canonical = parsed.variant == nil || (!parsed.queryPrefix && parsed.plainDigits)
            if parsed.variant == nil { singleItems.append(entry.name) }
            add(parsed.variant, top.kind, entry, relativePath: entry.name, canonical: canonical, countInName: top.count)
        } else if WorkspaceScanner.queryFolderKinds[parsed.rest] != nil {
            let folderName = Naming.queryFolderName(testID: id, variant: parsed.variant)
            testIssues.append(.warning("\(entry.name) is in the test folder; it belongs in \(folderName)/"))
        } else {
            testIssues.append(.warning("Unrecognised item: \(entry.name)"))
        }
    }

    private mutating func scanQueryFolder(_ folderEntry: WorkspaceScanner.Entry, variant: Int?) {
        slots.insert(variant)
        let entries: [WorkspaceScanner.Entry]
        do {
            entries = try WorkspaceScanner.listing(folderEntry.url, fileManager: fileManager)
        } catch {
            testIssues.append(.error("Couldn\u{2019}t read \(folderEntry.name): \(error.localizedDescription)"))
            return
        }
        for entry in entries {
            let relative = folderEntry.name + "/" + entry.name
            if !entry.isDirectory, let parsed = WorkspaceScanner.parse(entry.name, testID: id),
               parsed.rest == "annotation.md", parsed.variant == variant {
                readAnnotation(entry, relativePath: relative, variant: variant)
                continue
            }
            guard !entry.isDirectory, let parsed = WorkspaceScanner.parse(entry.name, testID: id),
                  let kind = WorkspaceScanner.queryFolderKinds[parsed.rest] else {
                testIssues.append(.warning("Unrecognised item: \(relative)"))
                continue
            }
            guard parsed.variant == variant else {
                let belongsTo = parsed.variant.map { "variant \($0)" } ?? "a single-RQ test"
                testIssues.append(.warning("\(relative) is named for \(belongsTo), not for the folder it is in"))
                continue
            }
            let canonical = variant == nil || (!parsed.queryPrefix && parsed.plainDigits)
            add(variant, kind, entry, relativePath: relative, canonical: canonical, countInName: nil)
        }
    }

    private mutating func readGroundTruth(_ entry: WorkspaceScanner.Entry) {
        do {
            let text = try TextSupport.readText(entry.url)
            let truth = GroundTruth(source: text, url: entry.url)
            groundTruth = truth
            if let problem = truth.problem {
                testIssues.append(.warning("\(entry.name): \(problem)"))
            }
        } catch {
            testIssues.append(.warning("Couldn\u{2019}t read \(entry.name): \(error.localizedDescription)"))
        }
    }

    private mutating func readAnnotation(_ entry: WorkspaceScanner.Entry, relativePath: String, variant: Int?) {
        do {
            let text = try TextSupport.readText(entry.url).trimmed
            annotations[variant] = (url: entry.url, text: text)
        } catch {
            testIssues.append(.warning("Couldn\u{2019}t read \(relativePath): \(error.localizedDescription)"))
        }
    }

    private mutating func add(_ variant: Int?, _ kind: ArtifactKind, _ entry: WorkspaceScanner.Entry,
                              relativePath: String, canonical: Bool, countInName: Int?) {
        slots.insert(variant)
        let file = ArtifactFile(kind: kind, url: entry.url, size: entry.size)
        found[variant, default: [:]][kind, default: []].append(
            Candidate(file: file, relativePath: relativePath, canonical: canonical, countInName: countInName))
    }

    // MARK: Checks

    private mutating func checkVariantNumbering(_ variants: [Int]) {
        if variants.count == 1 {
            testIssues.append(.warning("Only one variant was found; a multi-RQ test should have at least two"))
        }
        if variants.contains(0) {
            testIssues.append(.warning("Variants are numbered from 1, but there is a variant 0"))
        }
        if let highest = variants.last, highest > 1 {
            let present = Set(variants)
            let missing = (1...highest).filter { !present.contains($0) }
            if !missing.isEmpty {
                let noun = missing.count == 1 ? "variant" : "variants"
                testIssues.append(.warning("Variant numbering has a gap: no \(noun) "
                                           + TextSupport.list(missing.map(String.init))))
            }
        }
    }

    private func buildQuestion(_ variant: Int?) -> ResearchQuestion {
        var question = ResearchQuestion(testID: id, variant: variant)
        if let annotation = annotations[variant] {
            question.annotationFile = annotation.url
            question.annotation = annotation.text.isEmpty ? nil : annotation.text
        }
        let candidates = found[variant] ?? [:]
        for kind in ArtifactKind.allCases {
            let list = (candidates[kind] ?? []).sorted {
                ($0.canonical ? 0 : 1, $0.relativePath) < ($1.canonical ? 0 : 1, $1.relativePath)
            }
            guard let chosen = list.first else {
                let expected = Naming.relativePath(kind, testID: id, variant: variant)
                question.issues.append(.error("\(kind.title) is missing (expected \(expected))"))
                continue
            }
            if list.count > 1 {
                question.issues.append(.error("More than one \(kind.noun): "
                                              + TextSupport.list(list.map(\.relativePath))
                                              + "; showing \(chosen.relativePath)"))
            }
            if !chosen.canonical {
                let expected = Naming.relativePath(kind, testID: id, variant: variant,
                                                   referenceCount: chosen.countInName)
                question.issues.append(.warning("\(chosen.relativePath) doesn\u{2019}t follow the naming convention; expected \(expected)"))
            }
            question.files.append(chosen.file)
            if chosen.file.size == 0, kind != .rqText {
                question.issues.append(.warning("\(chosen.relativePath) is empty (0 bytes)"))
            }
            switch kind {
            case .rqText: readQuestion(chosen, into: &question)
            case .references: checkReferences(chosen, into: &question)
            default: break
            }
        }
        return question
    }

    private func readQuestion(_ candidate: Candidate, into question: inout ResearchQuestion) {
        do {
            let text = try TextSupport.readText(candidate.file.url).trimmed
            if text.isEmpty {
                question.issues.append(.error("The research question file is empty (\(candidate.relativePath))"))
            } else {
                question.question = text
            }
        } catch {
            question.issues.append(.error("Couldn\u{2019}t read \(candidate.relativePath): \(error.localizedDescription)"))
        }
    }

    private func checkReferences(_ candidate: Candidate, into question: inout ResearchQuestion) {
        let path = candidate.relativePath
        question.referencesInFileName = candidate.countInName
        if candidate.countInName == nil {
            let expected = Naming.fileName(.references, testID: id, variant: question.variant)
            question.issues.append(.error("\(path) has no reference count in its name (expected \(expected))"))
        }
        let summary: BibTeXSummary
        do {
            summary = try BibTeX.summary(contentsOf: candidate.file.url)
        } catch {
            question.issues.append(.error("Couldn\u{2019}t read \(path): \(error.localizedDescription)"))
            return
        }
        question.referencesFound = summary.entries
        if let named = candidate.countInName, named != summary.entries {
            question.issues.append(.error("\(path): the file name says \(TextSupport.plural(named, "reference")), "
                                          + "but the file has \(summary.entries)"))
        }
        if summary.endsInsideEntry {
            question.issues.append(.warning("\(path) ends inside an entry; check for unbalanced braces"))
        }
        // Clashing keys are listed, not raised as a problem (docs/FILE_FORMAT.md §3.4).
        question.keyClashes = summary.keyClashes
        if summary.entriesWithoutKey > 0 {
            question.issues.append(.warning("\(path) has \(TextSupport.plural(summary.entriesWithoutKey, "entry", "entries")) without a citation key"))
        }
    }
}
