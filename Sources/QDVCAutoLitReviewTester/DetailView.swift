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
                            ReferenceCountRow(question: question)
                            if !question.keyClashes.isEmpty {
                                KeyClashesRow(clashes: question.keyClashes)
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
        var parts = [test.kind.title, TextSupport.plural(test.totalReferences, "reference")]
        let issues = test.allIssues
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.count - errors
        if errors > 0 { parts.append(TextSupport.plural(errors, "error")) }
        if warnings > 0 { parts.append(TextSupport.plural(warnings, "warning")) }
        if issues.isEmpty { parts.append("complete") }
        return parts.joined(separator: ", ")
    }
}

private struct QuestionTextRow: View {
    let question: ResearchQuestion

    var body: some View {
        Text(question.question ?? "Research question not available")
            .font(.system(.body, design: .serif))
            .italic(question.question == nil)
            .foregroundStyle(question.question == nil ? Color.secondary : Color.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
    }
}

private struct ReferenceCountRow: View {
    let question: ResearchQuestion

    var body: some View {
        HStack(spacing: 6) {
            Label("References", systemImage: "number")
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

    private var foundText: String {
        switch (question.referencesFound, question.referencesInFileName) {
        case let (found?, named?) where found != named: return "\(found) found, file name says \(named)"
        case let (found?, _): return "\(found) found"
        case (nil, let named?): return "file name says \(named)"
        case (nil, nil): return "\u{2013}"
        }
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
