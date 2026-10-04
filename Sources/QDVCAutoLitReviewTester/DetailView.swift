import SwiftUI
import AutoLitReviewCore

/// Pane 3: the focused test. Each research question gets a section with its
/// text, its reference count and its artifacts; double-click an artifact (or
/// press ⌘↓) to open it in its default app.
struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let test = model.focusedTest {
            ScrollViewReader { proxy in
                List(selection: $model.selectedFileID) {
                    Section {
                        TestHeader(test: test)
                    }
                    Section("Ground Truth") {
                        GroundTruthRows(test: test)
                    }
                    if !test.issues.isEmpty {
                        Section("Test") {
                            ForEach(Array(test.issues.enumerated()), id: \.offset) { _, issue in
                                IssueRow(issue: issue)
                            }
                        }
                    }
                    ForEach(test.questions) { question in
                        Section(question.title) {
                            QuestionTextRow(question: question)
                                .id(question.id)
                            AnnotationRow(question: question)
                            ReferenceCountRow(question: question)
                            if let abstracts = question.abstracts, abstracts.total > 0 {
                                AbstractsRow(abstracts: abstracts)
                            }
                            if !question.keyClashes.isEmpty {
                                KeyClashesRow(clashes: question.keyClashes)
                            }
                            if !question.domChecks.isEmpty {
                                DOMChecksRow(results: question.domChecks)
                            }
                            ForEach(question.files) { file in
                                ArtifactRow(file: file)
                                    .tag(file.id)
                            }
                            ForEach(Array(question.issues.enumerated()), id: \.offset) { _, issue in
                                IssueRow(issue: issue)
                            }
                        }
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        Button("Open") { model.openFile(id: id) }
                        Button("Reveal in Finder") { model.reveal(URL(fileURLWithPath: id)) }
                        Button("Copy Path") { Platform.copy(id) }
                    }
                } primaryAction: { ids in
                    for id in ids { model.openFile(id: id) }
                }
                .onChange(of: model.selectedQuestionID) {
                    guard model.currentTab == .questions, let id = model.selectedQuestionID else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                }
            }
        } else {
            ContentUnavailableView("No Test Selected", systemImage: "doc.text.magnifyingglass",
                                   description: Text("Select a test to see its research questions, reference counts and files. Double-click a file to open it."))
        }
    }
}

private struct TestHeader: View {
    @Environment(AppModel.self) private var model
    let test: TestRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusIcon(status: test.status)
                    .font(.title2)
                Text(test.id)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                if test.kind == .multi {
                    Button {
                        model.beginAddVariants(test)
                    } label: {
                        Label("Add Variants", systemImage: "plus.square.on.square")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Add more variants to this test (\u{2325}\u{2318}N)")
                }
                if test.questions.count > 1, test.questions.contains(where: { $0.question != nil }) {
                    CopyButton(title: "Copy All Research Questions") { model.copyAllQuestions(test) }
                        .buttonStyle(.borderless)
                        .help("Copy every research question, one per line (\u{201C}Variant 1: \u{2026}\u{201D})")
                }
                Button {
                    model.openExternally(test.folder)
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open the test folder in Finder")
            }
            Text(summary)
                .foregroundStyle(.secondary)
            if test.hasMissingArtifacts {
                Button {
                    model.beginEditTest(test)
                } label: {
                    Label("Supply Missing Artifacts\u{2026}", systemImage: "tray.and.arrow.down")
                }
                .controlSize(.small)
                .help("Reopen the data entry form to add the missing files (\u{2325}\u{2318}E)")
            }
            if let date = test.dateText {
                Label("Exported \(date)", systemImage: "calendar")
                    .foregroundStyle(.secondary)
                    .help(test.exportDates.count > 1
                          ? "The variants\u{2019} BibTeX files were exported on different days"
                          : "From the BibTeX file\u{2019}s EXPORT DATE")
            }
            Text((test.folder.path as NSString).abbreviatingWithTildeInPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        var parts = [test.kind.inspectorTitle, TextSupport.plural(test.totalReferences, "reference")]
        let issues = test.allIssues
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.count - errors
        if errors > 0 { parts.append(TextSupport.plural(errors, "error")) }
        if warnings > 0 { parts.append(TextSupport.plural(warnings, "warning")) }
        if issues.isEmpty { parts.append("complete") }
        return parts.joined(separator: ", ")
    }
}

/// The research question, with a copy button beside it (and Copy in its
/// context menu), so it can be copied without selecting the text.
private struct QuestionTextRow: View {
    @Environment(AppModel.self) private var model
    let question: ResearchQuestion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(question.question ?? "Research question not available")
                .font(.system(.body, design: .serif))
                .italic(question.question == nil)
                .foregroundStyle(question.question == nil ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if question.question != nil {
                CopyButton(title: "Copy Research Question", iconOnly: true) { model.copyQuestion(question) }
                    .buttonStyle(.borderless)
                    .controlSize(.large)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Research Question") { model.copyQuestion(question) }
                .disabled(question.question == nil)
        }
    }
}

/// The tester's brief note on a research question, saved automatically to
/// `…_annotation.md` beside the question's other files.
private struct AnnotationRow: View {
    @Environment(AppModel.self) private var model
    let question: ResearchQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Annotation", systemImage: "square.and.pencil")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Annotation",
                      text: Binding(get: { model.annotationText(for: question) },
                                    set: { model.setAnnotation($0, for: question.id) }),
                      prompt: Text("Add a brief note about this research question"),
                      axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
        .padding(.vertical, 2)
        .help("Saved automatically to \(Naming.annotationFileName(testID: question.testID, variant: question.variant))")
    }
}

/// The ground truth: the APA 7 reference, with buttons to copy it or just
/// its DOI, and to edit it.
private struct GroundTruthRows: View {
    @Environment(AppModel.self) private var model
    let test: TestRun

    var body: some View {
        if let truth = test.groundTruth {
            if let reference = truth.reference {
                Text(reference.attributed)
                    .font(.system(.body, design: .serif))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Copy Reference") { model.copyGroundTruthReference(test) }
                        Button("Copy DOI") { model.copyGroundTruthDOI(test) }
                            .disabled(truth.doi == nil)
                    }
            } else if let problem = truth.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            HStack(spacing: 12) {
                CopyButton(title: "Copy Reference") { model.copyGroundTruthReference(test) }
                    .disabled(truth.reference == nil)
                    .help("Copy the APA 7 reference (italics kept when pasted into Word, Pages or Mail)")
                CopyButton(title: "Copy DOI") { model.copyGroundTruthDOI(test) }
                    .disabled(truth.doi == nil)
                    .help(truth.bareDOI.map { "Copy \($0)" } ?? "The entry has no DOI")
                Spacer()
                Button("Edit\u{2026}") { model.beginEditGroundTruth(test) }
            }
            .buttonStyle(.borderless)
        } else {
            HStack {
                Text("A published paper asking the same research questions, entered as BibTeX.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Add\u{2026}") { model.beginEditGroundTruth(test) }
            }
        }
    }
}

private struct ReferenceCountRow: View {
    let question: ResearchQuestion

    var body: some View {
        HStack(spacing: 6) {
            Label("References", systemImage: "number")
            if let exportedText {
                Text(exportedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(foundText)
                .monospacedDigit()
            switch question.countMatches {
            case true?:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Matches the count in the file name")
                    .accessibilityLabel("Matches the file name")
            case false?:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .help("The file name says \(question.referencesInFileName ?? 0)")
                    .accessibilityLabel("Does not match the file name")
            case nil:
                EmptyView()
            }
        }
    }

    private var exportedText: String? {
        guard question.exportDates.count > 0 else { return nil }
        return "exported " + (ExportDate.longRange(question.exportDates) ?? "")
    }

    private var foundText: String {
        switch (question.referencesFound, question.referencesInFileName) {
        case let (found?, named?) where found != named: return "\(found) found, file name says \(named)"
        case let (found?, _): return "\(found) found"
        case (nil, let named?): return "file name says \(named)"
        case (nil, nil): return "\u{2013}"
        }
    }
}

/// How many BibTeX entries have an abstract; a warning sign when more than
/// half don't (which is also a warning on the test).
private struct AbstractsRow: View {
    let abstracts: AbstractCoverage

    var body: some View {
        HStack(spacing: 6) {
            Label("Abstracts", systemImage: "text.alignleft")
            Spacer()
            Text(abstracts.description)
                .monospacedDigit()
                .foregroundStyle(abstracts.mostlyMissing ? Color.orange : Color.primary)
            if abstracts.mostlyMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("More than half of the entries have no abstract")
                    .accessibilityLabel("More than half have no abstract")
            }
        }
        .help("Entries in the BibTeX file with a non-empty abstract field")
    }
}

/// The DOM checks workspace.yml asks for, each passed or failed. A failure
/// is also a warning on the test.
private struct DOMChecksRow: View {
    let results: [DOMCheckResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("DOM checks", systemImage: "checklist")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                Label {
                    Text(result.title + (result.passed ? " found" : " not found"))
                } icon: {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.passed ? Color.green : Color.orange)
                        .accessibilityLabel(result.passed ? "Passed" : "Failed")
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 2)
        .help("Searched in the report DOM\u{2019}s text, as turned on in workspace.yml")
    }
}

/// Citation keys shared by separate entries, listed for information (they
/// aren't issues and don't affect the status), e.g. "Smith2025 (line 94) and
/// Smith2025 (line 255)".
private struct KeyClashesRow: View {
    let clashes: [KeyClash]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(Array(clashes.enumerated()), id: \.offset) { _, clash in
                Text(clash.description)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } label: {
            Label(TextSupport.plural(clashes.count, "clashing citation key"), systemImage: "key")
                .foregroundStyle(.secondary)
                .help("Citation keys shared by separate entries in the BibTeX file, with the line each entry starts on. Listed for information; they don\u{2019}t affect the status.")
        }
    }
}

private struct ArtifactRow: View {
    let file: ArtifactFile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help("Double-click to open \(file.name)")
    }

    private var detail: String {
        guard let size = file.size else { return file.kind.title }
        return file.kind.title + ", " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

private struct IssueRow: View {
    let issue: Issue

    var body: some View {
        Label {
            Text(issue.message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: issue.severity.systemImage)
                .foregroundStyle(issue.severity.color)
                .accessibilityLabel(issue.severity.title)
        }
        .font(.callout)
    }
}
