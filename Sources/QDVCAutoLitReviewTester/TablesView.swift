import SwiftUI
import AutoLitReviewCore

/// Tests tab, list: one row per test folder. Double-click opens the folder
/// in Finder; the artifacts themselves are opened from the detail pane.
struct TestsTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.testRows, selection: $model.selectedTestID, sortOrder: $model.testSortOrder) {
            TableColumn("", value: \.statusRank) { row in
                StatusIcon(status: row.status)
            }
            .width(22)

            TableColumn("Test ID", value: \.id) { row in
                Text(row.id).fontWeight(.medium)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Type", value: \.kind) { row in
                Text(row.kind).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 95)

            TableColumn("RQs", value: \.questionCount) { row in
                Text(String(row.questionCount)).monospacedDigit()
            }
            .width(min: 36, ideal: 42, max: 60)

            TableColumn("References", value: \.totalReferences) { row in
                Text(row.references).monospacedDigit().help("Total \(row.totalReferences)")
            }
            .width(min: 70, ideal: 100)

            TableColumn("Research Question", value: \.firstQuestion) { row in
                Text(row.firstQuestion).lineLimit(1).help(row.firstQuestion)
            }
            .width(min: 160, ideal: 320)

            TableColumn("Issues", value: \.issueCount) { row in
                Text(row.issueCount == 0 ? "" : String(row.issueCount)).monospacedDigit()
            }
            .width(min: 40, ideal: 50, max: 70)

            TableColumn("Export Date", value: \.dateRank) { row in
                Text(row.date).lineLimit(1).monospacedDigit().help(row.date)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Ground Truth", value: \.groundTruth) { row in
                Text(row.groundTruth).lineLimit(1).foregroundStyle(.secondary).help(row.groundTruth)
            }
            .width(min: 90, ideal: 150)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let test = model.scan?.test(id) {
                TestContextMenu(test: test)
            }
        } primaryAction: { ids in
            model.openTestFolder(ids.first)
        }
        .overlay { EmptyListOverlay(isEmpty: model.testRows.isEmpty, noun: "tests") }
        .onChange(of: model.testSortOrder) { model.refreshRows() }
        .onChange(of: model.selectedTestID) { model.selectedFileID = nil }
    }
}

/// Research Questions tab, list: the same sheet that Export writes, one row
/// per research question. Double-click opens that question's report PDF.
struct QuestionsTableView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.questionRows, selection: $model.selectedQuestionID, sortOrder: $model.questionSortOrder) {
            TableColumn("", value: \.statusRank) { row in
                StatusIcon(status: row.status)
            }
            .width(22)

            TableColumn("Test ID", value: \.testID) { row in
                Text(row.testID).fontWeight(.medium)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Variant", value: \.variantRank) { row in
                Text(row.variant).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 44, ideal: 54, max: 70)

            TableColumn("Research Question", value: \.question) { row in
                Text(row.question).lineLimit(2).help(row.question)
            }
            .width(min: 180, ideal: 380)

            TableColumn("Found", value: \.foundRank) { row in
                Text(row.found).monospacedDigit()
            }
            .width(min: 44, ideal: 54, max: 80)

            TableColumn("In Name", value: \.namedRank) { row in
                Text(row.named).monospacedDigit()
                    .foregroundStyle(row.match == false ? Color.red : Color.primary)
            }
            .width(min: 50, ideal: 60, max: 80)

            TableColumn("Match", value: \.matchRank) { row in
                switch row.match {
                case true?:
                    Image(systemName: "checkmark").foregroundStyle(.green).accessibilityLabel("Matches")
                case false?:
                    Image(systemName: "xmark").foregroundStyle(.red).accessibilityLabel("Does not match")
                case nil:
                    Text("\u{2013}").foregroundStyle(.secondary)
                }
            }
            .width(min: 40, ideal: 48, max: 60)

            TableColumn("Export Date", value: \.dateRank) { row in
                Text(row.date).lineLimit(1).monospacedDigit().help(row.date)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Annotation", value: \.annotation) { row in
                Text(row.annotation).lineLimit(1).foregroundStyle(.secondary).help(row.annotation)
            }
            .width(min: 90, ideal: 180)

            TableColumn("Key Clashes", value: \.clashCount) { row in
                Text(row.clashCount == 0 ? "" : String(row.clashCount))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help(row.clashCount == 0 ? "" : "Citation keys shared by separate entries; see the detail pane")
            }
            .width(min: 50, ideal: 70, max: 90)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let question = model.question(id: ids.first) {
                QuestionMenuItems(question: question)
                Divider()
                Button("Open Test Folder") { model.openTestFolder(question.testID) }
            }
        } primaryAction: { ids in
            guard let question = model.question(id: ids.first) else { return }
            if question.file(.report) != nil {
                model.open(.report, of: question)
            } else {
                model.openTestFolder(question.testID)
            }
        }
        .overlay { EmptyListOverlay(isEmpty: model.questionRows.isEmpty, noun: "research questions") }
        .onChange(of: model.questionSortOrder) { model.refreshRows() }
        .onChange(of: model.selectedQuestionID) { model.selectedFileID = nil }
    }
}

/// Open commands for one research question's artifacts.
struct QuestionMenuItems: View {
    @Environment(AppModel.self) private var model
    let question: ResearchQuestion

    var body: some View {
        ForEach(ArtifactKind.allCases) { kind in
            Button("Open \(kind.title)") { model.open(kind, of: question) }
                .disabled(question.file(kind) == nil)
        }
        Divider()
        Button("Copy Research Question") { model.copyQuestion(question) }
            .disabled(question.question == nil)
        Button("Copy Key Clashes") { model.copyKeyClashes(question) }
            .disabled(question.keyClashes.isEmpty)
    }
}

/// The Tests table's context menu: per-question commands directly for a
/// single-RQ test, in a submenu per variant otherwise.
struct TestContextMenu: View {
    @Environment(AppModel.self) private var model
    let test: TestRun

    var body: some View {
        if test.kind == .single, let question = test.questions.first {
            QuestionMenuItems(question: question)
        } else {
            ForEach(test.questions) { question in
                Menu(question.title) {
                    QuestionMenuItems(question: question)
                }
            }
        }
        if test.questions.count > 1 {
            Button("Copy All Research Questions") { model.copyAllQuestions(test) }
        }
        if test.kind == .multi {
            Divider()
            Button("Add Variants\u{2026}") { model.beginAddVariants(test) }
        }
        Divider()
        Button(test.groundTruth == nil ? "Add Ground Truth\u{2026}" : "Edit Ground Truth\u{2026}") {
            model.beginEditGroundTruth(test)
        }
        Button("Copy Ground Truth Reference") { model.copyGroundTruthReference(test) }
            .disabled(test.groundTruth?.reference == nil)
        Button("Copy Ground Truth DOI") { model.copyGroundTruthDOI(test) }
            .disabled(test.groundTruth?.doi == nil)
        Divider()
        Button("Open Test Folder") { model.openTestFolder(test.id) }
        Button("Reveal in Finder") { model.reveal(test.folder) }
        Button("Copy Test ID") { Platform.copy(test.id) }
    }
}

/// What an empty list says: the workspace has no tests, or nothing matches.
struct EmptyListOverlay: View {
    @Environment(AppModel.self) private var model
    let isEmpty: Bool
    let noun: String

    var body: some View {
        if isEmpty, model.scan != nil {
            if !model.searchText.trimmed.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            } else if model.filter != .all {
                ContentUnavailableView("No Matching \(noun.capitalized)", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Nothing matches the filter chosen in the sidebar."))
            } else {
                ContentUnavailableView {
                    Label("No Tests", systemImage: "folder")
                } description: {
                    Text("This workspace has no test folders yet. A test folder is named with A\u{2013}Z, 0\u{2013}9 and dashes, like ABCD-123.")
                } actions: {
                    Button("New Test\u{2026}") { model.beginNewTest() }
                }
            }
        }
    }
}
