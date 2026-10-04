import Foundation

/// One research question of an existing test, as the Edit Test sheet shows
/// it: what is already in the test, and what the tester supplies for the
/// rest (docs/FILE_FORMAT.md §6.2).
public struct CompletionQuestion: Hashable, Sendable, Identifiable {
    /// The research question's ID in the scan.
    public let id: String
    public let variant: Int?
    /// Artifacts already in the test: kind → path relative to the test folder.
    public let existing: [ArtifactKind: String]
    /// The research question's text, if the test has it (nil when its file
    /// is missing or empty).
    public let existingQuestion: String?
    public let existingAnnotation: String
    /// The folder (relative to the test) that new query files go in: the
    /// one already holding this question's query files, or the standard one.
    public let queryFolder: String
    /// What the tester supplies: text for a missing question, files for the
    /// missing artifacts, and the annotation (starting as the current one).
    public var input: DraftQuestion

    public init(question: ResearchQuestion, in test: TestRun) {
        id = question.id
        variant = question.variant
        var existing: [ArtifactKind: String] = [:]
        for file in question.files {
            existing[file.kind] = WorkspaceScanner.relativePath(of: file.url, in: test.folder)
        }
        self.existing = existing
        existingQuestion = question.question
        existingAnnotation = question.annotation ?? ""
        let queryPath = existing[.rqText] ?? existing[.queryAsked] ?? existing[.responseReceived]
        queryFolder = queryPath.flatMap { $0.split(separator: "/").first.map(String.init) }
            ?? Naming.queryFolderName(testID: test.id, variant: question.variant)
        var input = DraftQuestion()
        input.annotation = existingAnnotation
        self.input = input
    }

    /// What the test lacks for this question: artifacts with no file, and
    /// the research question when its text is missing or empty.
    public var missing: [ArtifactKind] {
        ArtifactKind.allCases.filter { kind in
            kind == .rqText ? existingQuestion == nil : existing[kind] == nil
        }
    }

    /// What will still be missing after saving what has been supplied.
    public var stillMissing: [ArtifactKind] {
        missing.filter { kind in
            kind == .rqText ? input.text.trimmed.isEmpty : input.files[kind] == nil
        }
    }

    public var annotationChanged: Bool { input.annotation.trimmed != existingAnnotation }

    public var hasChanges: Bool { stillMissing.count != missing.count || annotationChanged }

    /// The new files, relative to the test folder. A research question file
    /// that exists but is empty is written over; nothing else ever is.
    func plannedFiles(testID: String) -> [PlannedFile] {
        var planned: [PlannedFile] = []
        for kind in missing {
            let name = Naming.fileName(kind, testID: testID, variant: variant,
                                       referenceCount: input.referenceSummary?.entries)
            let path = kind.isInQueryFolder ? queryFolder + "/" + name : name
            if kind == .rqText {
                let text = input.text.trimmed
                guard !text.isEmpty else { continue }
                planned.append(PlannedFile(relativePath: existing[.rqText] ?? path, source: .text(text + "\n")))
            } else if let url = input.files[kind] {
                planned.append(PlannedFile(relativePath: path, source: .copy(url)))
            }
        }
        return planned
    }

    /// The empty research question file this would write over, if any.
    var replaceablePath: String? {
        existingQuestion == nil && !input.text.trimmed.isEmpty ? existing[.rqText] : nil
    }
}

/// Everything entered on the Edit Test sheet for an existing test.
public struct CompletionDraft: Hashable, Sendable {
    public let testID: String
    public let kind: TestKind
    public var questions: [CompletionQuestion]

    public init(test: TestRun) {
        testID = test.id
        kind = test.kind
        questions = test.questions.map { CompletionQuestion(question: $0, in: test) }
    }

    public var hasChanges: Bool { questions.contains { $0.hasChanges } }

    /// Whether the test lacks anything at all.
    public var hasMissing: Bool { questions.contains { !$0.missing.isEmpty } }

    /// What stops saving: only BibTeX files that can't be read. (Saving with
    /// artifacts still missing is fine; they can be supplied later.)
    public var problems: [String] {
        questions.compactMap { question in
            question.input.referenceError.map { error in
                DraftQuestion.sentence(question.variant.map { "Variant \($0): " } ?? "",
                                       "the references file can\u{2019}t be read (\(error))")
            }
        }
    }

    /// "Variant 2: report PDF and report DOM (HTML)", one per question with
    /// anything still missing after saving.
    public var stillMissingSummary: [String] {
        questions.compactMap { question in
            let missing = question.stillMissing
            guard !missing.isEmpty else { return nil }
            let scope = question.variant.map { "Variant \($0): " } ?? ""
            return scope + TextSupport.list(missing.map(\.noun))
        }
    }

    /// The files saving will add, relative to the test folder.
    public func plannedFiles() -> [PlannedFile] {
        questions.flatMap { $0.plannedFiles(testID: testID) }
    }
}

extension TestCreator {
    /// Supplies a test's missing artifacts: copies the chosen files in under
    /// the standard names (the originals are only read), writes a missing
    /// research question, and saves changed annotations. Files already in the
    /// test are never changed; if a new name is already taken (say, the test
    /// changed meanwhile), nothing is written. Only an empty `RQ_asked.md` is
    /// written over, with the text typed for it. If a copy fails part-way,
    /// the files added so far are removed again. Returns how many files were
    /// added or filled in.
    @discardableResult
    public static func complete(_ draft: CompletionDraft, test: TestRun,
                                fileManager: FileManager = .default) throws -> Int {
        var draft = draft
        for index in draft.questions.indices { draft.questions[index].input.recountReferences() }
        let problems = draft.problems
        guard problems.isEmpty else { throw NewTestError.notReady(problems) }

        let planned = draft.plannedFiles()
        let replaceable = Set(draft.questions.compactMap(\.replaceablePath))
        for file in planned where !replaceable.contains(file.relativePath) {
            if fileManager.fileExists(atPath: test.folder.appendingPathComponent(file.relativePath).path) {
                throw NewTestError.wouldOverwrite("\(test.id)/\(file.relativePath)")
            }
        }

        var added: [URL] = []
        do {
            for file in planned {
                let target = test.folder.appendingPathComponent(file.relativePath)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch file.source {
                case .copy(let source):
                    try fileManager.copyItem(at: source, to: target)
                    added.append(target)
                case .text(let text):
                    if replaceable.contains(file.relativePath) {
                        try Data(text.utf8).write(to: target, options: .atomic)
                    } else {
                        try Data(text.utf8).write(to: target, options: .withoutOverwriting)
                        added.append(target)
                    }
                }
            }
            for question in draft.questions where question.annotationChanged {
                guard let original = test.questions.first(where: { $0.id == question.id }) else { continue }
                try WorkspaceWriter.saveAnnotation(question.input.annotation, for: original, in: test,
                                                   fileManager: fileManager)
            }
        } catch {
            for url in added { try? fileManager.removeItem(at: url) }
            throw NewTestError.failed(error.localizedDescription)
        }
        return planned.count
    }
}

extension TestRun {
    /// Whether any research question lacks an artifact or its text, so the
    /// Edit Test sheet has something to supply.
    public var hasMissingArtifacts: Bool {
        questions.contains { question in
            question.question == nil || ArtifactKind.suppliedFiles.contains { question.file($0) == nil }
        }
    }
}
