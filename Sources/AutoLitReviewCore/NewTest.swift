import Foundation

/// One research question on the New Test sheet: its text and the files
/// chosen for it (the originals; nothing is copied until the test is
/// created).
public struct DraftQuestion: Hashable, Sendable, Identifiable {
    public let id: UUID
    public var text: String
    /// An optional note, saved as `…_annotation.md` (docs/FILE_FORMAT.md §2.5).
    public var annotation: String = ""
    public private(set) var files: [ArtifactKind: URL] = [:]
    /// What the chosen BibTeX file holds, counted when it was chosen.
    public private(set) var referenceSummary: BibTeXSummary?
    /// Why the chosen BibTeX file couldn't be read, if it couldn't.
    public private(set) var referenceError: String?

    public init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }

    /// Chooses (or, with nil, clears) the file for an artifact. Choosing a
    /// BibTeX file counts its entries straight away.
    public mutating func setFile(_ url: URL?, for kind: ArtifactKind) {
        files[kind] = url
        if kind == .references { recountReferences() }
    }

    /// Counts the chosen BibTeX file's entries again (it may have changed).
    public mutating func recountReferences() {
        referenceSummary = nil
        referenceError = nil
        guard let url = files[.references] else { return }
        do {
            referenceSummary = try BibTeX.summary(contentsOf: url)
        } catch {
            referenceError = error.localizedDescription
        }
    }

    /// The supplied-file slots that are still empty.
    public var missingFiles: [ArtifactKind] {
        ArtifactKind.suppliedFiles.filter { files[$0] == nil }
    }

    /// What still stops this question from being saved, each prefixed with
    /// `scope` ("Variant 2: "), or capitalised when there is no scope.
    public func problems(scope: String) -> [String] {
        var problems: [String] = []
        if text.trimmed.isEmpty {
            problems.append(Self.sentence(scope, "enter the research question"))
        }
        if !missingFiles.isEmpty {
            problems.append(Self.sentence(scope, "add the " + TextSupport.list(missingFiles.map(\.noun))))
        }
        if let referenceError {
            problems.append(Self.sentence(scope, "the references file can\u{2019}t be read (\(referenceError))"))
        }
        return problems
    }

    /// The files this question becomes as `variant` (nil for single-RQ) of
    /// the test `testID`, relative to the test folder: the artifacts chosen,
    /// the research question, and the annotation if one was written.
    public func plannedFiles(testID: String, variant: Int?) -> [PlannedFile] {
        var planned: [PlannedFile] = []
        for artifact in ArtifactKind.allCases {
            let path = Naming.relativePath(artifact, testID: testID, variant: variant,
                                           referenceCount: referenceSummary?.entries)
            if artifact == .rqText {
                planned.append(PlannedFile(relativePath: path, source: .text(text.trimmed + "\n")))
            } else if let url = files[artifact] {
                planned.append(PlannedFile(relativePath: path, source: .copy(url)))
            }
        }
        let note = annotation.trimmed
        if !note.isEmpty {
            let path = Naming.queryFolderName(testID: testID, variant: variant) + "/"
                + Naming.annotationFileName(testID: testID, variant: variant)
            planned.append(PlannedFile(relativePath: path, source: .text(note + "\n")))
        }
        return planned
    }

    static func sentence(_ scope: String, _ text: String) -> String {
        guard scope.isEmpty, let first = text.first else { return scope + text }
        return first.uppercased() + text.dropFirst()
    }
}

/// Everything entered on the New Test sheet.
public struct NewTestDraft: Hashable, Sendable {
    /// A multi-RQ test needs at least this many research questions.
    public static let minimumVariants = 2

    public var id: String = ""
    public var kind: TestKind = .single {
        didSet { ensureMinimumQuestions() }
    }
    /// Always at least one. A single-RQ test uses only the first; the others
    /// are kept, so switching to single and back loses nothing.
    public var questions: [DraftQuestion] = [DraftQuestion()]

    public init() {}

    /// The research questions the test will have.
    public var activeQuestions: [DraftQuestion] {
        kind == .single ? Array(questions.prefix(1)) : questions
    }

    public mutating func addVariant() {
        questions.append(DraftQuestion())
    }

    public var canRemoveVariant: Bool {
        kind == .multi && questions.count > Self.minimumVariants
    }

    public mutating func removeVariant(_ id: UUID) {
        guard canRemoveVariant else { return }
        questions.removeAll { $0.id == id }
    }

    private mutating func ensureMinimumQuestions() {
        let needed = kind == .multi ? Self.minimumVariants : 1
        while questions.count < needed { questions.append(DraftQuestion()) }
    }

    /// The variant number of a research question (nil for single-RQ).
    public func variant(at index: Int) -> Int? {
        kind == .single ? nil : index + 1
    }

    // MARK: Validation

    /// Why the test ID can't be used, or nil when it can. `exists` says
    /// whether a folder of that name is already in the workspace.
    public func idProblem(exists: (String) -> Bool) -> String? {
        if id.isEmpty { return "Enter a test ID" }
        if !Naming.isValidTestID(id) { return "Test IDs use only A\u{2013}Z, 0\u{2013}9 and dashes" }
        if exists(id) { return "A test called \(id) already exists in this workspace" }
        return nil
    }

    /// Everything that still stops the test from being created, in the
    /// order of the sheet; empty when it can be saved.
    public func problems(exists: (String) -> Bool) -> [String] {
        var problems: [String] = []
        if let problem = idProblem(exists: exists) { problems.append(problem) }
        if kind == .multi, questions.count < Self.minimumVariants {
            problems.append("Add at least \(Self.minimumVariants) research questions")
        }
        for (index, question) in activeQuestions.enumerated() {
            problems += question.problems(scope: variant(at: index).map { "Variant \($0): " } ?? "")
        }
        return problems
    }

    // MARK: Plan

    /// The files the test folder will hold, relative to it, in the order
    /// they are written. `testID` defaults to the draft's ID (the sheet
    /// passes a placeholder while none has been typed).
    public func plannedFiles(testID: String? = nil) -> [PlannedFile] {
        let id = testID ?? self.id
        return activeQuestions.enumerated().flatMap { index, question in
            question.plannedFiles(testID: id, variant: variant(at: index))
        }
    }
}

/// One file of a new test folder.
public struct PlannedFile: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// Copied from this file, which is left as it is.
        case copy(URL)
        /// Written with this text (UTF-8).
        case text(String)
    }

    public let relativePath: String
    public let source: Source

    public init(relativePath: String, source: Source) {
        self.relativePath = relativePath
        self.source = source
    }
}

public enum NewTestError: LocalizedError, Equatable {
    case notReady([String])
    case alreadyExists(String)
    case failed(String)
    /// Variants can only be added to a multi-RQ test.
    case notMultiRQ(String)
    /// Adding variants would overwrite this item (a path in the test folder).
    case wouldOverwrite(String)

    public var errorDescription: String? {
        switch self {
        case .notReady(let problems): return problems.joined(separator: "\n")
        case .alreadyExists(let id): return "A test called \(id) already exists in this workspace."
        case .failed(let reason): return "The files couldn\u{2019}t be created: \(reason)"
        case .notMultiRQ(let id):
            return "Variants can only be added to a multi-RQ test; \(id) has a single research question."
        case .wouldOverwrite(let path): return "\(path) already exists, and nothing is ever overwritten."
        }
    }
}

/// Creates a test folder from a draft.
public enum TestCreator {
    /// Copies the chosen files into a new test folder under their canonical
    /// names and writes the research question files. The originals are only
    /// read, never moved or changed. The folder is assembled under a hidden
    /// name and renamed into place at the end, so a failure part-way leaves
    /// nothing behind and the scanner never sees a half-made test.
    @discardableResult
    public static func create(_ draft: NewTestDraft, in workspace: URL,
                              fileManager: FileManager = .default) throws -> URL {
        let exists: (String) -> Bool = { name in
            fileManager.fileExists(atPath: workspace.appendingPathComponent(name).path)
        }
        // Count again in case a BibTeX file changed since it was chosen.
        var draft = draft
        for index in draft.questions.indices { draft.questions[index].recountReferences() }

        let problems = draft.problems(exists: exists)
        guard problems.isEmpty else {
            if Naming.isValidTestID(draft.id), exists(draft.id) { throw NewTestError.alreadyExists(draft.id) }
            throw NewTestError.notReady(problems)
        }

        let destination = workspace.appendingPathComponent(draft.id, isDirectory: true)
        let staging = workspace.appendingPathComponent(".\(draft.id).creating-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            for planned in draft.plannedFiles() {
                let target = staging.appendingPathComponent(planned.relativePath)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                switch planned.source {
                case .copy(let source):
                    try fileManager.copyItem(at: source, to: target)
                case .text(let text):
                    try Data(text.utf8).write(to: target, options: .withoutOverwriting)
                }
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw NewTestError.failed(error.localizedDescription)
        }
        return destination
    }
}

/// New variants for an existing multi-RQ test. They are numbered on from the
/// test's highest variant, so 1–3 gain 4, 5 and so on.
public struct AddVariantsDraft: Hashable, Sendable {
    public let testID: String
    /// The number the first new variant gets.
    public let firstVariant: Int
    /// Always at least one.
    public var questions: [DraftQuestion] = [DraftQuestion()]

    public init(testID: String, firstVariant: Int) {
        self.testID = testID
        self.firstVariant = max(1, firstVariant)
    }

    /// Numbers the new variants after the test's highest one.
    public init(test: TestRun) {
        self.init(testID: test.id, firstVariant: (test.questions.compactMap(\.variant).max() ?? 0) + 1)
    }

    public func variant(at index: Int) -> Int { firstVariant + index }

    public mutating func addVariant() { questions.append(DraftQuestion()) }

    public var canRemoveVariant: Bool { questions.count > 1 }

    public mutating func removeVariant(_ id: UUID) {
        guard canRemoveVariant else { return }
        questions.removeAll { $0.id == id }
    }

    /// Everything that still stops the variants from being added.
    public func problems() -> [String] {
        questions.enumerated().flatMap { index, question in
            question.problems(scope: "Variant \(variant(at: index)): ")
        }
    }

    /// The new files, relative to the test folder.
    public func plannedFiles() -> [PlannedFile] {
        questions.enumerated().flatMap { index, question in
            question.plannedFiles(testID: testID, variant: variant(at: index))
        }
    }
}

extension TestCreator {
    /// Adds the draft's variants to an existing multi-RQ test, copying the
    /// chosen files under the standard names (the originals are only read)
    /// and writing the research questions and annotations. Nothing in the
    /// test is changed or overwritten: if any new name is already taken, it
    /// stops before writing. The files are assembled in a hidden folder
    /// inside the test and moved into place at the end. Returns the variant
    /// numbers added.
    @discardableResult
    public static func addVariants(_ draft: AddVariantsDraft, to test: TestRun,
                                   fileManager: FileManager = .default) throws -> [Int] {
        guard test.kind == .multi else { throw NewTestError.notMultiRQ(test.id) }
        var draft = draft
        for index in draft.questions.indices { draft.questions[index].recountReferences() }
        let problems = draft.problems()
        guard problems.isEmpty else { throw NewTestError.notReady(problems) }

        let planned = draft.plannedFiles()
        // The top-level items the variants add: their query folders and files.
        var topLevel: [String] = []
        for file in planned {
            let name = String(file.relativePath.split(separator: "/").first ?? "")
            if !topLevel.contains(name) { topLevel.append(name) }
        }
        for name in topLevel where fileManager.fileExists(atPath: test.folder.appendingPathComponent(name).path) {
            throw NewTestError.wouldOverwrite("\(test.id)/\(name)")
        }

        let staging = test.folder.appendingPathComponent(".adding-variants-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            for file in planned {
                let target = staging.appendingPathComponent(file.relativePath)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch file.source {
                case .copy(let source): try fileManager.copyItem(at: source, to: target)
                case .text(let text): try Data(text.utf8).write(to: target, options: .withoutOverwriting)
                }
            }
            for name in topLevel {
                try fileManager.moveItem(at: staging.appendingPathComponent(name),
                                         to: test.folder.appendingPathComponent(name))
            }
            try? fileManager.removeItem(at: staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw NewTestError.failed(error.localizedDescription)
        }
        return draft.questions.indices.map { draft.variant(at: $0) }
    }
}

/// Decides which slot each dropped file goes in, so several files can be
/// dropped at once, anywhere on a research question.
public enum DropRouting {
    public struct Result: Equatable {
        /// Files for slots, in drop order.
        public var assignments: [Assignment] = []
        /// A dropped .md or .txt file whose text becomes the research question.
        public var questionText: URL?
        /// Files that fit no slot (or a slot already filled by this drop).
        public var rejected: [URL] = []

        public init() {}
    }

    public struct Assignment: Equatable {
        public let kind: ArtifactKind
        public let url: URL
    }

    /// Routes `urls` by extension. The two screenshots are both PNG, so for
    /// them the name decides ("response" or "received" → response, "query"
    /// or "asked" → query); failing that, a single file goes to the slot it
    /// was dropped on (`preferring`), and otherwise to the first empty one.
    public static func route(_ urls: [URL], preferring preferred: ArtifactKind? = nil,
                             current: [ArtifactKind: URL] = [:]) -> Result {
        var result = Result()
        var taken = Set<ArtifactKind>()
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ArtifactKind.rqText.acceptedExtensions.contains(ext) {
                result.questionText = url
                continue
            }
            let candidates = ArtifactKind.suppliedFiles.filter { $0.acceptedExtensions.contains(ext) }
            guard !candidates.isEmpty else {
                result.rejected.append(url)
                continue
            }
            let choice: ArtifactKind
            if candidates.count == 1 {
                choice = candidates[0]
            } else if urls.count == 1, let preferred, candidates.contains(preferred) {
                choice = preferred
            } else if let guess = guessScreenshot(url, among: candidates) {
                choice = guess
            } else if let preferred, candidates.contains(preferred), !taken.contains(preferred) {
                choice = preferred
            } else if let empty = candidates.first(where: { !taken.contains($0) && current[$0] == nil }) {
                choice = empty
            } else if let free = candidates.first(where: { !taken.contains($0) }) {
                choice = free
            } else {
                choice = candidates[0]
            }
            guard taken.insert(choice).inserted else {
                result.rejected.append(url)
                continue
            }
            result.assignments.append(Assignment(kind: choice, url: url))
        }
        return result
    }

    static func guessScreenshot(_ url: URL, among candidates: [ArtifactKind]) -> ArtifactKind? {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if candidates.contains(.responseReceived), name.contains("response") || name.contains("received") {
            return .responseReceived
        }
        if candidates.contains(.queryAsked), name.contains("query") || name.contains("asked") {
            return .queryAsked
        }
        return nil
    }
}
