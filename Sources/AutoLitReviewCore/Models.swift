import Foundation

/// Whether a test asked one research question or several ("variants").
public enum TestKind: String, CaseIterable, Sendable, Hashable {
    case single
    case multi

    public var title: String {
        switch self {
        case .single: return "Single RQ"
        case .multi: return "Multiple RQs"
        }
    }
}

/// How serious a problem is. Errors make a test incomplete or wrong (a
/// missing artifact, a reference count that doesn't match); warnings are
/// worth a look but don't stop the test from being used (a file named the
/// old way, a stray file, an entry without a citation key).
public enum Severity: Int, CaseIterable, Sendable, Hashable, Comparable {
    case warning = 1
    case error = 2

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The overall state of a test or of one research question.
public enum Status: Int, CaseIterable, Sendable, Hashable, Comparable {
    case complete = 0
    case warnings = 1
    case errors = 2

    public static func < (lhs: Status, rhs: Status) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .complete: return "Complete"
        case .warnings: return "Warnings"
        case .errors: return "Errors"
        }
    }

    /// The status a list of issues adds up to: the worst severity among them.
    public init(issues: [Issue]) {
        switch issues.map(\.severity).max() {
        case .error?: self = .errors
        case .warning?: self = .warnings
        case nil: self = .complete
        }
    }
}

/// One problem found while checking a test.
public struct Issue: Hashable, Sendable {
    public let severity: Severity
    public let message: String

    public init(_ severity: Severity, _ message: String) {
        self.severity = severity
        self.message = message
    }

    public static func error(_ message: String) -> Issue { Issue(.error, message) }
    public static func warning(_ message: String) -> Issue { Issue(.warning, message) }
}

/// The six artifacts every research question needs. The first three live in
/// the query folder; the other three sit directly in the test folder.
public enum ArtifactKind: String, CaseIterable, Sendable, Hashable, Identifiable {
    case queryAsked
    case responseReceived
    case rqText
    case references
    case report
    case reportDOM

    public var id: Self { self }

    public var title: String {
        switch self {
        case .queryAsked: return "Query screenshot"
        case .responseReceived: return "Response screenshot"
        case .rqText: return "Research question"
        case .references: return "References"
        case .report: return "Report (PDF)"
        case .reportDOM: return "Report (HTML DOM)"
        }
    }

    /// The title as it reads mid-sentence ("add the report PDF").
    public var noun: String {
        switch self {
        case .queryAsked: return "query screenshot"
        case .responseReceived: return "response screenshot"
        case .rqText: return "research question"
        case .references: return "references file"
        case .report: return "report PDF"
        case .reportDOM: return "report DOM (HTML)"
        }
    }

    /// The extension the file is saved with.
    public var fileExtension: String {
        switch self {
        case .queryAsked, .responseReceived: return "png"
        case .rqText: return "md"
        case .references: return "bib"
        case .report: return "pdf"
        case .reportDOM: return "html"
        }
    }

    /// Extensions accepted when a file is dropped on the New Test sheet
    /// (lowercase). The copy is always saved with `fileExtension`.
    public var acceptedExtensions: [String] {
        switch self {
        case .queryAsked, .responseReceived: return ["png"]
        case .rqText: return ["md", "txt"]
        case .references: return ["bib"]
        case .report: return ["pdf"]
        case .reportDOM: return ["html", "htm"]
        }
    }

    /// True for the artifacts kept in the query folder.
    public var isInQueryFolder: Bool {
        switch self {
        case .queryAsked, .responseReceived, .rqText: return true
        case .references, .report, .reportDOM: return false
        }
    }

    /// The part of the file name after the `ID_` or `ID_variantN_` prefix.
    /// Only `references` has a count in it; pass nil to get the `n<count>`
    /// placeholder used in messages.
    public func nameSuffix(referenceCount: Int? = nil) -> String {
        switch self {
        case .queryAsked: return "query_asked.png"
        case .responseReceived: return "response_received.png"
        case .rqText: return "RQ_asked.md"
        case .references: return "references_n\(referenceCount.map(String.init) ?? "<count>").bib"
        case .report: return "report.pdf"
        case .reportDOM: return "report_DOM.html"
        }
    }

    /// The artifacts a tester supplies as files on the New Test sheet (the
    /// research question is typed instead, and saved as `RQ_asked.md`).
    public static let suppliedFiles: [ArtifactKind] = [.queryAsked, .responseReceived, .references, .report, .reportDOM]
}

/// An artifact found on disk.
public struct ArtifactFile: Hashable, Sendable, Identifiable {
    public let kind: ArtifactKind
    public let url: URL
    /// Size in bytes, or nil if it couldn't be read.
    public let size: Int64?

    public init(kind: ArtifactKind, url: URL, size: Int64?) {
        self.kind = kind
        self.url = url
        self.size = size
    }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
}

/// One research question of a test (the only one, or one variant) and what
/// was found for it.
public struct ResearchQuestion: Hashable, Sendable, Identifiable {
    public let testID: String
    /// The variant number, or nil for a single-RQ test.
    public let variant: Int?
    /// The text of `RQ_asked.md`, trimmed; nil when the file is missing or
    /// can't be read.
    public var question: String?
    /// The artifacts found, in `ArtifactKind` order (at most one per kind).
    public var files: [ArtifactFile]
    /// The number of entries in the BibTeX file, if there is a readable one.
    public var referencesFound: Int?
    /// The `n<count>` in the BibTeX file's name, if it has one.
    public var referencesInFileName: Int?
    /// Problems with this research question's artifacts.
    public var issues: [Issue]
    /// Citation keys shared by separate entries in the BibTeX file. These are
    /// for information only: they don't count as issues or affect the status.
    public var keyClashes: [KeyClash]
    /// The tester's note on this research question (`…_annotation.md`,
    /// trimmed), if there is one. Optional; never an issue when absent.
    public var annotation: String?
    /// Where the annotation was read from, if it exists.
    public var annotationFile: URL?
    /// The "EXPORT DATE:" dates in the BibTeX file, earliest first.
    public var exportDates: [ExportDate] = []

    public init(testID: String, variant: Int?, question: String? = nil, files: [ArtifactFile] = [],
                referencesFound: Int? = nil, referencesInFileName: Int? = nil, issues: [Issue] = [],
                keyClashes: [KeyClash] = []) {
        self.testID = testID
        self.variant = variant
        self.question = question
        self.files = files
        self.referencesFound = referencesFound
        self.referencesInFileName = referencesInFileName
        self.issues = issues
        self.keyClashes = keyClashes
        self.annotation = nil
        self.annotationFile = nil
    }

    public var id: String { "\(testID)#\(variant ?? 0)" }

    /// "Variant 2", or "Research question" for a single-RQ test.
    public var title: String { variant.map { "Variant \($0)" } ?? "Research question" }

    /// Whether the count in the file name matches the entries in the file;
    /// nil when either is unknown.
    public var countMatches: Bool? {
        guard let found = referencesFound, let named = referencesInFileName else { return nil }
        return found == named
    }

    public var status: Status { Status(issues: issues) }

    public func file(_ kind: ArtifactKind) -> ArtifactFile? {
        files.first { $0.kind == kind }
    }
}

/// One test run: a folder named like `ABCD-123` in the workspace.
public struct TestRun: Hashable, Sendable, Identifiable {
    /// The folder name, which is the test ID.
    public let id: String
    public let folder: URL
    public var kind: TestKind
    /// One entry for a single-RQ test; one per variant (in variant order)
    /// for a multi-RQ test.
    public var questions: [ResearchQuestion]
    /// Problems that belong to the test as a whole (variant numbering,
    /// unrecognised items).
    public var issues: [Issue]
    /// The "ground truth" paper for the test (`ID_ground_truth.bib`), if the
    /// tester has entered one. Optional; never an issue when absent.
    public var groundTruth: GroundTruth?

    public init(id: String, folder: URL, kind: TestKind, questions: [ResearchQuestion], issues: [Issue],
                groundTruth: GroundTruth? = nil) {
        self.id = id
        self.folder = folder
        self.kind = kind
        self.questions = questions
        self.issues = issues
        self.groundTruth = groundTruth
    }

    /// Every issue of the test and of its research questions.
    public var allIssues: [Issue] { issues + questions.flatMap(\.issues) }

    public var status: Status { Status(issues: allIssues) }

    /// The status of one research question's row, counting the test-level
    /// issues too (they affect every row).
    public func rowStatus(_ question: ResearchQuestion) -> Status {
        Status(issues: issues + question.issues)
    }

    /// The export dates of all the test's BibTeX files, earliest first: the
    /// test's date, or its range of dates.
    public var exportDates: [ExportDate] {
        Array(Set(questions.flatMap(\.exportDates))).sorted()
    }

    /// "2 October 2026" or "30 September – 2 October 2026"; nil when no
    /// BibTeX file gives an export date.
    public var dateText: String? { ExportDate.longRange(exportDates) }

    /// Total of the references found across all research questions.
    public var totalReferences: Int { questions.compactMap(\.referencesFound).reduce(0, +) }
}

/// The result of scanning a workspace folder.
public struct WorkspaceScan: Hashable, Sendable {
    public let root: URL
    /// The tests, in natural order of their IDs (ABC-2 before ABC-10).
    public var tests: [TestRun]
    /// Names of items in the workspace folder that aren't test folders
    /// (anything that isn't a folder named with A–Z, 0–9 and dashes). They
    /// are listed, not treated as problems: exports often end up here.
    public var otherItems: [String]

    public init(root: URL, tests: [TestRun], otherItems: [String]) {
        self.root = root
        self.tests = tests
        self.otherItems = otherItems
    }

    public var questionCount: Int { tests.reduce(0) { $0 + $1.questions.count } }

    public func test(_ id: String) -> TestRun? { tests.first { $0.id == id } }
}
