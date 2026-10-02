import Foundation

/// A test's "ground truth": one published paper that asks the same research
/// questions, entered by the tester as a single BibTeX entry and kept in
/// `ID/ID_ground_truth.bib` (docs/FILE_FORMAT.md §2.5).
public struct GroundTruth: Hashable, Sendable {
    /// The BibTeX text as entered (trimmed).
    public let source: String
    /// The file it was read from; nil for a preview of unsaved text.
    public let url: URL?
    /// How many reference entries the text holds (it should be exactly one).
    public let entryCount: Int
    /// The first entry, if there is one.
    public let entry: BibEntry?

    public init(source: String, url: URL? = nil) {
        self.source = source.trimmed
        self.url = url
        let entries = BibTeX.entries(in: source)
        entryCount = entries.count
        entry = entries.first
    }

    /// The APA 7 reference, with the DOI as `doi:…`.
    public var reference: FormattedReference? { entry.map(APA7.format) }

    /// `doi:10.1234/abcd`, if the entry has a DOI.
    public var doi: String? { entry.flatMap(APA7.doi(of:)) }

    /// "Smith et al. (2024)".
    public var shortCitation: String? { entry.map(APA7.shortCitation) }

    /// What's wrong with the text, if anything: it must hold exactly one entry.
    public var problem: String? {
        switch entryCount {
        case 0: return "No BibTeX entry was found"
        case 1: return nil
        default: return "It holds \(entryCount) entries; a ground truth is a single paper, so only the first is used"
        }
    }
}

/// Saves what the tester enters in the inspector. These are the only files
/// the app writes into existing test folders, and only when asked to.
public enum WorkspaceWriter {
    /// Where a test's ground truth lives: the file it was read from, or
    /// `ID/ID_ground_truth.bib`.
    public static func groundTruthURL(for test: TestRun) -> URL {
        test.groundTruth?.url ?? test.folder.appendingPathComponent(Naming.groundTruthFileName(testID: test.id))
    }

    /// Where a research question's annotation lives: the file it was read
    /// from, or `…_annotation.md` in the folder holding its query files
    /// (whatever that folder is called), or else the standard query folder.
    public static func annotationURL(for question: ResearchQuestion, in test: TestRun) -> URL {
        if let existing = question.annotationFile { return existing }
        let folder = (question.file(.rqText) ?? question.file(.queryAsked) ?? question.file(.responseReceived))?
            .url.deletingLastPathComponent()
            ?? test.folder.appendingPathComponent(Naming.queryFolderName(testID: test.id, variant: question.variant),
                                                  isDirectory: true)
        return folder.appendingPathComponent(Naming.annotationFileName(testID: test.id, variant: question.variant))
    }

    /// Writes the ground truth (trimmed, one trailing newline); empty text
    /// removes the file. Returns the URL written, or nil when removed.
    @discardableResult
    public static func saveGroundTruth(_ text: String, for test: TestRun,
                                       fileManager: FileManager = .default) throws -> URL? {
        try save(text, to: groundTruthURL(for: test), fileManager: fileManager)
    }

    /// Writes the annotation (trimmed, one trailing newline), creating the
    /// query folder if it is missing; empty text removes the file.
    @discardableResult
    public static func saveAnnotation(_ text: String, for question: ResearchQuestion, in test: TestRun,
                                      fileManager: FileManager = .default) throws -> URL? {
        try save(text, to: annotationURL(for: question, in: test), fileManager: fileManager)
    }

    private static func save(_ text: String, to url: URL, fileManager: FileManager) throws -> URL? {
        let content = text.trimmed
        if content.isEmpty {
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            return nil
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((content + "\n").utf8).write(to: url, options: .atomic)
        return url
    }
}
