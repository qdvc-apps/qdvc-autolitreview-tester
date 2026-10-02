import AppKit
import Observation
import UniformTypeIdentifiers
import AutoLitReviewCore

/// The window's tabs (the segmented control in the toolbar).
enum AppTab: String, CaseIterable, Identifiable {
    case tests, questions

    var id: Self { self }

    var title: String {
        switch self {
        case .tests: return "Tests"
        case .questions: return "Research Questions"
        }
    }
}

/// The sidebar's filters. They apply to tests on the Tests tab and to
/// research-question rows on the Research Questions tab.
enum TestFilter: String, CaseIterable, Identifiable, Hashable {
    case all, complete, warnings, errors, single, multi

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .complete: return "Complete"
        case .warnings: return "With Warnings"
        case .errors: return "With Errors"
        case .single: return "Single RQ"
        case .multi: return "Multiple RQs"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .complete: return "checkmark.circle"
        case .warnings: return "exclamationmark.triangle"
        case .errors: return "xmark.octagon"
        case .single: return "doc.text"
        case .multi: return "doc.on.doc"
        }
    }

    func matches(status: Status, kind: TestKind) -> Bool {
        switch self {
        case .all: return true
        case .complete: return status == .complete
        case .warnings: return status == .warnings
        case .errors: return status == .errors
        case .single: return kind == .single
        case .multi: return kind == .multi
        }
    }
}

enum ExportFormat: CaseIterable {
    case csv, html, markdown

    var title: String {
        switch self {
        case .csv: return "CSV"
        case .html: return "HTML"
        case .markdown: return "Markdown"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .html: return "html"
        case .markdown: return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .html: return .html
        case .markdown: return UTType("net.daringfireball.markdown")
            ?? UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
        }
    }
}

/// A value snapshot of one Tests-tab row. The `…Rank` values are what the
/// sortable columns compare.
struct TestRow: Identifiable, Hashable {
    let id: String
    let kind: String
    let questionCount: Int
    /// "67" or "67, 23, 41".
    let references: String
    let totalReferences: Int
    let firstQuestion: String
    let status: Status
    let statusRank: Int
    let issueCount: Int
    /// "Smith et al. (2024)", or "" when there is no ground truth.
    let groundTruth: String
    /// The export date or range ("" when unknown), and the ISO form to sort by.
    let date: String
    let dateRank: String

    init(_ test: TestRun) {
        id = test.id
        kind = test.kind.title
        questionCount = test.questions.count
        references = test.questions.map { $0.referencesFound.map(String.init) ?? "\u{2013}" }.joined(separator: ", ")
        totalReferences = test.totalReferences
        let questions = test.questions.compactMap(\.question)
        firstQuestion = questions.count > 1 ? "\(questions[0]) (+\(questions.count - 1) more)" : (questions.first ?? "")
        status = test.status
        statusRank = test.status.rawValue
        issueCount = test.allIssues.count
        groundTruth = test.groundTruth?.shortCitation ?? (test.groundTruth == nil ? "" : "\u{2013}")
        date = test.dateText ?? ""
        dateRank = ExportDate.isoRange(test.exportDates) ?? ""
    }
}

/// A value snapshot of one Research Questions-tab row.
struct QuestionRow: Identifiable, Hashable {
    let id: String
    let testID: String
    let variant: String
    let variantRank: Int
    let question: String
    let found: String
    let foundRank: Int
    let named: String
    let namedRank: Int
    let match: Bool?
    let matchRank: Int
    /// Citation keys shared by separate entries (for information).
    let clashCount: Int
    /// The annotation on one line ("" when there is none).
    let annotation: String
    let date: String
    let dateRank: String
    let status: Status
    let statusRank: Int

    init(_ test: TestRun, _ question: ResearchQuestion) {
        id = question.id
        testID = test.id
        variant = question.variant.map(String.init) ?? "\u{2013}"
        variantRank = question.variant ?? 0
        self.question = question.question ?? ""
        found = question.referencesFound.map(String.init) ?? "\u{2013}"
        foundRank = question.referencesFound ?? -1
        named = question.referencesInFileName.map(String.init) ?? "\u{2013}"
        namedRank = question.referencesInFileName ?? -1
        match = question.countMatches
        matchRank = question.countMatches.map { $0 ? 2 : 0 } ?? 1
        clashCount = question.keyClashes.count
        annotation = (question.annotation ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
        date = ExportDate.longRange(question.exportDates) ?? ""
        dateRank = ExportDate.isoRange(question.exportDates) ?? ""
        let rowStatus = test.rowStatus(question)
        status = rowStatus
        statusRank = rowStatus.rawValue
    }
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// The one sheet that can be open over the main window.
enum ActiveSheet: Identifiable, Equatable {
    case newTest
    /// Editing the ground truth of the test with this ID.
    case groundTruth(String)

    var id: String {
        switch self {
        case .newTest: return "new-test"
        case .groundTruth(let testID): return "ground-truth-\(testID)"
        }
    }
}

/// All state for the single main window. Every change goes through here,
/// and `refreshRows()` rebuilds what the tables show from the last scan.
@MainActor
@Observable
final class AppModel {
    private(set) var workspaceURL: URL?
    private(set) var scan: WorkspaceScan?
    private(set) var isLoading = false
    private(set) var recentWorkspaces: [String] = Prefs.recentWorkspaces

    var currentTab: AppTab = .tests
    var sidebarSelection: TestFilter? = .all
    var searchText = ""
    var testSortOrder: [KeyPathComparator<TestRow>] = [KeyPathComparator(\TestRow.id)]
    var questionSortOrder: [KeyPathComparator<QuestionRow>] = [
        KeyPathComparator(\QuestionRow.testID), KeyPathComparator(\QuestionRow.variantRank),
    ]
    var selectedTestID: String?
    var selectedQuestionID: String?
    /// The artifact selected in the detail pane (its path).
    var selectedFileID: String?

    var activeSheet: ActiveSheet?
    var alert: AlertInfo?

    private(set) var testRows: [TestRow] = []
    private(set) var questionRows: [QuestionRow] = []

    /// Annotations as typed, by research-question ID, until the scan shows
    /// the same text on disk. Saving happens a moment after typing stops.
    private(set) var annotationDrafts: [String: String] = [:]
    @ObservationIgnored private var annotationSaveTasks: [String: Task<Void, Never>] = [:]

    /// Bumped by every scan, so only the latest one's result is applied.
    @ObservationIgnored private var scanGeneration = 0

    // MARK: - Derived

    var hasWorkspace: Bool { workspaceURL != nil }

    var windowTitle: String { workspaceURL?.lastPathComponent ?? "QDVC Auto Lit Review Tester" }

    var filter: TestFilter { sidebarSelection ?? .all }

    /// The test shown in the detail pane: the selected test, or the test of
    /// the selected research question.
    var focusedTest: TestRun? {
        guard let scan else { return nil }
        switch currentTab {
        case .tests:
            guard let id = selectedTestID else { return nil }
            return scan.test(id)
        case .questions:
            guard let id = selectedQuestionID else { return nil }
            return scan.tests.first { test in test.questions.contains { $0.id == id } }
        }
    }

    /// The research question that the Test menu's Open commands act on: the
    /// selected row on the Research Questions tab, the question of the
    /// selected artifact, or a single-RQ test's only question.
    var focusedQuestion: ResearchQuestion? {
        guard let test = focusedTest else { return nil }
        if currentTab == .questions, let id = selectedQuestionID {
            return test.questions.first { $0.id == id }
        }
        if let fileID = selectedFileID,
           let question = test.questions.first(where: { $0.files.contains { $0.id == fileID } }) {
            return question
        }
        return test.questions.count == 1 ? test.questions[0] : nil
    }

    /// The badge for a sidebar filter: tests on the Tests tab, research
    /// questions on the other (search is not applied, as in Mail).
    func count(_ filter: TestFilter) -> Int {
        guard let scan else { return 0 }
        switch currentTab {
        case .tests:
            return scan.tests.filter { filter.matches(status: $0.status, kind: $0.kind) }.count
        case .questions:
            return scan.tests.reduce(0) { total, test in
                total + test.questions.filter { filter.matches(status: test.rowStatus($0), kind: test.kind) }.count
            }
        }
    }

    /// The text of the status bar under the list.
    var statusLine: String {
        guard let scan else { return "" }
        var parts = [TextSupport.plural(scan.tests.count, "test"),
                     TextSupport.plural(scan.questionCount, "research question")]
        let errors = scan.tests.filter { $0.status == .errors }.count
        let warnings = scan.tests.filter { $0.status == .warnings }.count
        if errors > 0 { parts.append("\(errors) with errors") }
        if warnings > 0 { parts.append("\(warnings) with warnings") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Workspace

    /// Called once when the window appears: opens a folder given on the
    /// command line (`swift run QDVCAutoLitReviewTester sample-workspace`),
    /// or else reopens the last workspace if that preference is on.
    func startUp() {
        guard workspaceURL == nil else { return }
        let argument = CommandLine.arguments.dropFirst().first { argument in
            var isDirectory: ObjCBool = false
            return !argument.hasPrefix("-")
                && FileManager.default.fileExists(atPath: argument, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        if let argument {
            openWorkspace(URL(fileURLWithPath: argument, isDirectory: true))
        } else if Prefs.reopenLast, let last = Prefs.lastWorkspace, FileManager.default.fileExists(atPath: last) {
            openWorkspace(URL(fileURLWithPath: last, isDirectory: true))
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose the folder that holds your test folders (such as ABCD-123)."
        if panel.runModal() == .OK, let url = panel.url {
            openWorkspace(url)
        }
    }

    func openWorkspace(_ url: URL) {
        flushAnnotations()
        annotationDrafts = [:]
        guard Platform.isDirectory(url) else {
            alert = AlertInfo(title: "Workspace folder not found",
                              message: (url.path as NSString).abbreviatingWithTildeInPath)
            removeRecent(url.path)
            return
        }
        workspaceURL = url.standardizedFileURL
        scan = nil
        selectedTestID = nil
        selectedQuestionID = nil
        selectedFileID = nil
        searchText = ""
        sidebarSelection = .all
        refreshRows()
        let path = url.standardizedFileURL.path
        Prefs.lastWorkspace = path
        recentWorkspaces = [path] + recentWorkspaces.filter { $0 != path }
        Prefs.recentWorkspaces = recentWorkspaces
        recentWorkspaces = Prefs.recentWorkspaces
        rescan()
    }

    func closeWorkspace() {
        flushAnnotations()
        annotationDrafts = [:]
        scanGeneration += 1
        workspaceURL = nil
        scan = nil
        isLoading = false
        selectedTestID = nil
        selectedQuestionID = nil
        selectedFileID = nil
        activeSheet = nil
        Prefs.lastWorkspace = nil
        refreshRows()
    }

    func revealWorkspace() {
        guard let workspaceURL else { return }
        Platform.revealInFinder([workspaceURL])
    }

    func clearRecents() {
        recentWorkspaces = []
        Prefs.recentWorkspaces = []
    }

    private func removeRecent(_ path: String) {
        recentWorkspaces.removeAll { $0 == path }
        Prefs.recentWorkspaces = recentWorkspaces
    }

    /// View → Refresh (⌘R).
    func refresh() { rescan() }

    func appBecameActive() {
        guard Prefs.refreshOnActivate, hasWorkspace, !isLoading else { return }
        rescan()
    }

    /// Scans the workspace off the main thread and applies the result. With
    /// `selecting`, that test is selected afterwards (after New Test).
    func rescan(selecting id: String? = nil) {
        guard let root = workspaceURL else { return }
        scanGeneration += 1
        let generation = scanGeneration
        if scan == nil { isLoading = true }
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<WorkspaceScan, Error> in
                Result { try WorkspaceScanner.scan(root) }
            }.value
            guard let self, generation == self.scanGeneration else { return }
            self.isLoading = false
            switch result {
            case .success(let scan):
                self.apply(scan, selecting: id)
            case .failure(let error):
                self.alert = AlertInfo(title: "Couldn\u{2019}t read the workspace", message: error.localizedDescription)
                if self.scan == nil { self.closeWorkspace() }
            }
        }
    }

    private func apply(_ newScan: WorkspaceScan, selecting id: String?) {
        scan = newScan
        if let id, newScan.test(id) != nil {
            currentTab = .tests
            sidebarSelection = .all
            searchText = ""
            selectedTestID = id
        }
        if let selected = selectedTestID, newScan.test(selected) == nil { selectedTestID = nil }
        if let selected = selectedQuestionID,
           !newScan.tests.contains(where: { test in test.questions.contains { $0.id == selected } }) {
            selectedQuestionID = nil
        }
        reconcileAnnotationDrafts()
        if let file = selectedFileID {
            let stillThere = focusedTest?.questions.contains(where: { question in
                question.files.contains(where: { $0.id == file })
            }) ?? false
            if !stillThere { selectedFileID = nil }
        }
        refreshRows()
    }

    // MARK: - Rows

    func refreshRows() {
        guard let scan else {
            testRows = []
            questionRows = []
            return
        }
        let filter = self.filter
        let query = searchText.trimmed
        var tests: [TestRow] = []
        var questions: [QuestionRow] = []
        for test in scan.tests {
            let idMatches = query.isEmpty || test.id.localizedCaseInsensitiveContains(query)
            let truthMatches = !query.isEmpty
                && (test.groundTruth?.reference?.plain ?? "").localizedCaseInsensitiveContains(query)
            let anyQuestionMatches = test.questions.contains { questionMatches($0, query) }
            if filter.matches(status: test.status, kind: test.kind), idMatches || truthMatches || anyQuestionMatches {
                tests.append(TestRow(test))
            }
            for question in test.questions where filter.matches(status: test.rowStatus(question), kind: test.kind) {
                if idMatches || questionMatches(question, query) {
                    questions.append(QuestionRow(test, question))
                }
            }
        }
        tests.sort(using: testSortOrder)
        questions.sort(using: questionSortOrder)
        testRows = tests
        questionRows = questions
    }

    /// A research question matches a search by its text or its annotation.
    private func questionMatches(_ question: ResearchQuestion, _ query: String) -> Bool {
        (question.question ?? "").localizedCaseInsensitiveContains(query)
            || annotationText(for: question).localizedCaseInsensitiveContains(query)
    }

    /// Keeps the detail pane on the same test when switching tabs.
    func tabChanged(from old: AppTab) {
        selectedFileID = nil
        switch (old, currentTab) {
        case (.tests, .questions):
            if let id = selectedTestID, let test = scan?.test(id),
               let first = test.questions.first, questionRows.contains(where: { $0.id == first.id }) {
                selectedQuestionID = first.id
            }
        case (.questions, .tests):
            if let test = scan?.tests.first(where: { test in test.questions.contains { $0.id == selectedQuestionID } }),
               testRows.contains(where: { $0.id == test.id }) {
                selectedTestID = test.id
            }
        default:
            break
        }
        refreshRows()
    }

    // MARK: - Opening artifacts

    /// Opens a file in its default app, or a folder in Finder.
    func openExternally(_ url: URL) {
        if !Platform.openExternally(url) {
            alert = AlertInfo(title: "Couldn\u{2019}t open \(url.lastPathComponent)",
                              message: "No app is set to open this kind of file.")
        }
    }

    func openFile(id: String) {
        openExternally(URL(fileURLWithPath: id))
    }

    func open(_ kind: ArtifactKind, of question: ResearchQuestion?) {
        guard let file = question?.file(kind) else { return }
        openExternally(file.url)
    }

    func openTestFolder(_ id: String?) {
        guard let id, let test = scan?.test(id) else { return }
        openExternally(test.folder)
    }

    /// The query folder holding a research question's screenshots and text.
    func openQueryFolder(_ question: ResearchQuestion?) {
        guard let file = question?.file(.rqText) ?? question?.file(.queryAsked) ?? question?.file(.responseReceived) else {
            return
        }
        openExternally(file.url.deletingLastPathComponent())
    }

    func reveal(_ url: URL) {
        Platform.revealInFinder([url])
    }

    func revealFocused() {
        if let id = selectedFileID {
            reveal(URL(fileURLWithPath: id))
        } else if let test = focusedTest {
            reveal(test.folder)
        }
    }

    /// Copies the clashing citation keys, one clash per line.
    func copyKeyClashes(_ question: ResearchQuestion?) {
        guard let clashes = question?.keyClashes, !clashes.isEmpty else { return }
        Platform.copy(clashes.map(\.description).joined(separator: "\n"))
    }

    func copyQuestion(_ question: ResearchQuestion?) {
        guard let text = question?.question else { return }
        Platform.copy(text)
    }

    /// Every research question of a test, one per line ("Variant 1: …").
    func copyAllQuestions(_ test: TestRun?) {
        guard let test else { return }
        let lines = test.questions.compactMap { question -> String? in
            guard let text = question.question else { return nil }
            return question.variant.map { "Variant \($0): \(text)" } ?? text
        }
        guard !lines.isEmpty else { return }
        Platform.copy(lines.joined(separator: "\n"))
    }

    /// The ground truth's APA 7 reference, as rich text (italics kept when
    /// pasted into Word, Pages or Mail) and plain text.
    func copyGroundTruthReference(_ test: TestRun?) {
        guard let reference = test?.groundTruth?.reference else { return }
        Platform.copy(reference)
    }

    /// The ground truth's DOI alone, `10.1234/abcd` (no `doi:` prefix).
    func copyGroundTruthDOI(_ test: TestRun?) {
        guard let doi = test?.groundTruth?.bareDOI else { return }
        Platform.copy(doi)
    }

    // MARK: - Ground truth

    func beginEditGroundTruth(_ test: TestRun?) {
        guard let test else { return }
        activeSheet = .groundTruth(test.id)
    }

    /// Saves (or, with empty text, removes) a test's ground truth; returns a
    /// problem to show, or nil when done (the sheet closes).
    func saveGroundTruth(_ text: String, for testID: String) -> String? {
        guard let test = scan?.test(testID) else { return "The test \(testID) is no longer in the workspace." }
        do {
            try WorkspaceWriter.saveGroundTruth(text, for: test)
        } catch {
            return error.localizedDescription
        }
        activeSheet = nil
        rescan()
        return nil
    }

    // MARK: - Annotations

    /// What the annotation field shows: the text being typed, else what is on disk.
    func annotationText(for question: ResearchQuestion) -> String {
        annotationDrafts[question.id] ?? question.annotation ?? ""
    }

    /// Called as the tester types; saves a moment after typing stops.
    func setAnnotation(_ text: String, for questionID: String) {
        annotationDrafts[questionID] = text
        annotationSaveTasks[questionID]?.cancel()
        annotationSaveTasks[questionID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.saveAnnotation(questionID)
        }
    }

    /// Saves every annotation still waiting (when the app goes to the
    /// background or quits, or the workspace closes).
    func flushAnnotations() {
        for (id, task) in annotationSaveTasks {
            task.cancel()
            saveAnnotation(id)
        }
        annotationSaveTasks = [:]
    }

    private func saveAnnotation(_ questionID: String) {
        annotationSaveTasks[questionID] = nil
        guard let text = annotationDrafts[questionID], let scan,
              let t = scan.tests.firstIndex(where: { test in test.questions.contains { $0.id == questionID } }),
              let q = scan.tests[t].questions.firstIndex(where: { $0.id == questionID }) else { return }
        let test = scan.tests[t]
        let question = test.questions[q]
        let trimmed = text.trimmed
        guard trimmed != (question.annotation ?? "") || (trimmed.isEmpty && question.annotationFile != nil) else { return }
        do {
            let url = try WorkspaceWriter.saveAnnotation(text, for: question, in: test)
            self.scan?.tests[t].questions[q].annotation = trimmed.isEmpty ? nil : trimmed
            self.scan?.tests[t].questions[q].annotationFile = url
            refreshRows()
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t save the annotation", message: error.localizedDescription)
        }
    }

    /// After a scan: a draft that matches the file is kept (it may have
    /// trailing spaces still being typed); one that doesn't, with no save
    /// pending, means the file was changed elsewhere, so the file wins.
    private func reconcileAnnotationDrafts() {
        guard let scan else { return }
        for (id, draft) in annotationDrafts where annotationSaveTasks[id] == nil {
            let onDisk = scan.tests.lazy.flatMap(\.questions).first { $0.id == id }?.annotation ?? ""
            if draft.trimmed != onDisk { annotationDrafts[id] = nil }
        }
    }

    func question(id: String?) -> ResearchQuestion? {
        guard let id, let scan else { return nil }
        for test in scan.tests {
            if let question = test.questions.first(where: { $0.id == id }) { return question }
        }
        return nil
    }

    // MARK: - Export

    func export(_ format: ExportFormat) {
        guard let scan, let root = workspaceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if format == .markdown {
            // Meant to sit at the top of the workspace as its README, so the
            // links to each test's files work on GitHub and the like.
            panel.nameFieldStringValue = "README.md"
            panel.directoryURL = root
            panel.message = "Exports every test as Markdown, with links to its files. Save it in the workspace folder as README.md for the links to work on GitHub."
        } else {
            panel.nameFieldStringValue = "\(root.lastPathComponent)-tests-\(Naming.dateStamp(Date())).\(format.fileExtension)"
            panel.message = "Exports every test in the workspace, one row per research question."
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        switch format {
        case .csv:
            data = Exporter.csvData(scan.tests)
        case .html:
            data = Data(Exporter.html(scan.tests, workspaceName: root.lastPathComponent, generated: Date()).utf8)
        case .markdown:
            data = Data(Exporter.markdown(scan.tests, workspaceName: root.lastPathComponent, generated: Date(),
                                          linkBase: url.deletingLastPathComponent()).utf8)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t export", message: error.localizedDescription)
            return
        }
        if url.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path {
            rescan()
        }
    }

    // MARK: - New Test

    func beginNewTest() {
        guard hasWorkspace else { return }
        activeSheet = .newTest
    }

    /// Whether a folder of that name is already in the workspace.
    func testExists(_ id: String) -> Bool {
        guard let root = workspaceURL, !id.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path)
    }

    /// Creates the test; returns a problem to show (keeping the sheet open),
    /// or nil when it was created (the sheet closes and the test is selected).
    func createTest(_ draft: NewTestDraft) -> String? {
        guard let root = workspaceURL else { return "No workspace is open." }
        do {
            try TestCreator.create(draft, in: root)
        } catch {
            return error.localizedDescription
        }
        activeSheet = nil
        rescan(selecting: draft.id)
        return nil
    }
}
