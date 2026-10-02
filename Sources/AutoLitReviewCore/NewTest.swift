import Foundation

/// One research question on the New Test sheet: its text and the files
/// chosen for it (the originals; nothing is copied until the test is
/// created).
public struct DraftQuestion: Hashable, Sendable, Identifiable {
    public let id: UUID
    public var text: String
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
            let scope = variant(at: index).map { "Variant \($0): " } ?? ""
            if question.text.trimmed.isEmpty {
                problems.append(Self.sentence(scope, "enter the research question"))
            }
            let missing = question.missingFiles
            if !missing.isEmpty {
                problems.append(Self.sentence(scope, "add the " + TextSupport.list(missing.map(\.noun))))
            }
            if let error = question.referenceError {
                problems.append(Self.sentence(scope, "the references file can\u{2019}t be read (\(error))"))
            }
        }
        return problems
    }

    private static func sentence(_ scope: String, _ text: String) -> String {
        guard scope.isEmpty, let first = text.first else { return scope + text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Plan

    /// The files the test folder will hold, relative to it, in the order
    /// they are written. `testID` defaults to the draft's ID (the sheet
    /// passes a placeholder while none has been typed).
    public func plannedFiles(testID: String? = nil) -> [PlannedFile] {
        let id = testID ?? self.id
        var planned: [PlannedFile] = []
        for (index, question) in activeQuestions.enumerated() {
            let variant = self.variant(at: index)
            for artifact in ArtifactKind.allCases {
                let path = Naming.relativePath(artifact, testID: id, variant: variant,
                                               referenceCount: question.referenceSummary?.entries)
                if artifact == .rqText {
                    planned.append(PlannedFile(relativePath: path, source: .text(question.text.trimmed + "\n")))
                } else if let url = question.files[artifact] {
                    planned.append(PlannedFile(relativePath: path, source: .copy(url)))
                }
            }
        }
        return planned
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

    public var errorDescription: String? {
        switch self {
        case .notReady(let problems): return problems.joined(separator: "\n")
        case .alreadyExists(let id): return "A test called \(id) already exists in this workspace."
        case .failed(let reason): return "The test folder couldn\u{2019}t be created: \(reason)"
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
