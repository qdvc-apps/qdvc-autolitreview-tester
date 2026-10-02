import AppKit
import SwiftUI
import AutoLitReviewCore

/// File → New Test (⌘N): enter the test ID, choose single or multiple
/// research questions, type each question and drop its files. Create Test
/// is enabled once everything is there; the files are copied, never moved.
struct NewTestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = NewTestDraft()
    /// Shown under the ID field after a character was dropped from it.
    @State private var idNote: String?
    /// Shown in the footer after a dropped file couldn't be used.
    @State private var dropNote: String?
    /// Why the last Create Test failed.
    @State private var createProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Test")
                    .font(.title2.weight(.semibold))
                Text("Drop files on a research question \u{2014} several at once is fine \u{2014} or use Choose\u{2026}. They are copied into the new test folder under the standard names; the originals stay where they are.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 6)

            Form {
                Section {
                    TextField("Test ID", text: idBinding, prompt: Text("ABCD-123"))
                    if let note = idNote ?? idProblemToShow {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Research questions", selection: $draft.kind) {
                        Text("Single RQ").tag(TestKind.single)
                        Text("Multiple RQs (variants)").tag(TestKind.multi)
                    }
                    .pickerStyle(.segmented)
                }

                if draft.kind == .single {
                    Section("Research Question") {
                        QuestionEditor(question: $draft.questions[0], onNote: { dropNote = $0 })
                    }
                } else {
                    ForEach($draft.questions) { $question in
                        Section {
                            QuestionEditor(question: $question, onNote: { dropNote = $0 })
                        } header: {
                            HStack {
                                Text("Variant \(variantNumber(of: question.id))")
                                Spacer()
                                if draft.canRemoveVariant {
                                    Button("Remove Variant", role: .destructive) {
                                        draft.removeVariant(question.id)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.callout)
                                }
                            }
                        }
                    }
                    Section {
                        Button {
                            draft.addVariant()
                        } label: {
                            Label("Add Variant", systemImage: "plus")
                        }
                    }
                }

                Section {
                    DisclosureGroup("Files to be created") {
                        ForEach(plannedPaths, id: \.self) { path in
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack(alignment: .center, spacing: 12) {
                footerMessage
                Spacer(minLength: 12)
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Test") {
                    createProblem = model.createTest(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!problems.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 660, height: 740)
        .onChange(of: draft) { createProblem = nil }
    }

    // MARK: Footer

    @ViewBuilder
    private var footerMessage: some View {
        if let createProblem {
            Label(createProblem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        } else if let dropNote {
            Label(dropNote, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .lineLimit(3)
        } else if let first = problems.first {
            let more = problems.count > 1 ? " (and \(problems.count - 1) more)" : ""
            Label(first + more, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .help(problems.joined(separator: "\n"))
        } else {
            Label("Ready to create \(draft.id)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    // MARK: Derived

    private var problems: [String] {
        draft.problems(exists: { model.testExists($0) })
    }

    /// Only "already exists" is worth showing under the field as you type;
    /// the other ID problems are in the footer.
    private var idProblemToShow: String? {
        model.testExists(draft.id) ? draft.idProblem(exists: { model.testExists($0) }) : nil
    }

    private func variantNumber(of id: UUID) -> Int {
        (draft.questions.firstIndex { $0.id == id } ?? 0) + 1
    }

    /// Every file the folder will hold (whether or not chosen yet).
    private var plannedPaths: [String] {
        let id = draft.id.isEmpty ? "ABCD-123" : draft.id
        var paths = [id + "/"]
        for (index, question) in draft.activeQuestions.enumerated() {
            let variant = draft.variant(at: index)
            for kind in ArtifactKind.allCases {
                paths.append("  " + Naming.relativePath(kind, testID: id, variant: variant,
                                                        referenceCount: question.referenceSummary?.entries))
            }
        }
        return paths
    }

    /// The Test ID field: a–z become A–Z; spaces and anything else that
    /// isn't allowed are refused with a beep and a note.
    private var idBinding: Binding<String> {
        Binding(
            get: { draft.id },
            set: { typed in
                let cleaned = Naming.sanitizeTestID(typed)
                if cleaned.removedSomething {
                    NSSound.beep()
                    idNote = "Test IDs use only A\u{2013}Z, 0\u{2013}9 and dashes (no spaces)."
                } else {
                    idNote = nil
                }
                draft.id = cleaned.id
            })
    }
}

/// One research question: its text and its five file slots.
private struct QuestionEditor: View {
    @Binding var question: DraftQuestion
    let onNote: (String?) -> Void

    var body: some View {
        TextField("Question", text: $question.text,
                  prompt: Text("The research question exactly as it was asked"), axis: .vertical)
            .lineLimit(2...8)
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls, preferring: nil)
            }
        ForEach(ArtifactKind.suppliedFiles) { kind in
            FileSlotRow(kind: kind,
                        url: question.files[kind],
                        summary: kind == .references ? question.referenceSummary : nil,
                        error: kind == .references ? question.referenceError : nil,
                        onDrop: { urls in handleDrop(urls, preferring: kind) },
                        onChoose: { choose(kind) },
                        onClear: { question.setFile(nil, for: kind) })
        }
    }

    private func handleDrop(_ urls: [URL], preferring kind: ArtifactKind?) -> Bool {
        let files = urls.filter { !Platform.isDirectory($0) }
        let result = DropRouting.route(files, preferring: kind, current: question.files)
        for assignment in result.assignments {
            question.setFile(assignment.url, for: assignment.kind)
        }
        if let textURL = result.questionText, let text = try? TextSupport.readText(textURL) {
            question.text = text.trimmed
        }
        let unused = result.rejected + urls.filter { Platform.isDirectory($0) }
        if unused.isEmpty {
            onNote(nil)
        } else {
            NSSound.beep()
            onNote("Not used: " + TextSupport.list(unused.map(\.lastPathComponent), limit: 3)
                   + ". Each slot takes one file: .png, .bib, .pdf or .html (and .md or .txt for the question).")
        }
        return !result.assignments.isEmpty || result.questionText != nil
    }

    private func choose(_ kind: ArtifactKind) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Platform.contentTypes(forExtensions: kind.acceptedExtensions)
        panel.message = "Choose the \(kind.noun)."
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            question.setFile(url, for: kind)
            onNote(nil)
        }
    }
}

/// A drop target for one artifact, showing what has been chosen.
private struct FileSlotRow: View {
    let kind: ArtifactKind
    let url: URL?
    let summary: BibTeXSummary?
    let error: String?
    let onDrop: ([URL]) -> Bool
    let onChoose: () -> Void
    let onClear: () -> Void

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: url == nil ? "circle.dashed" : (error == nil ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .font(.title3)
                .foregroundStyle(url == nil ? Color.secondary : (error == nil ? Color.green : Color.red))
                .accessibilityHidden(true)
            Image(systemName: kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(error == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url?.path ?? "")
            }
            Spacer(minLength: 8)
            if url != nil {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove the \(kind.noun)")
                .accessibilityLabel("Remove the \(kind.noun)")
            }
            Button(url == nil ? "Choose\u{2026}" : "Change\u{2026}") { onChoose() }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            onDrop(urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard let url else {
            return "Drop a ." + kind.acceptedExtensions.joined(separator: " or .") + " file here"
        }
        if let error { return "\(url.lastPathComponent): can\u{2019}t be read (\(error))" }
        if let summary { return "\(url.lastPathComponent), \(TextSupport.plural(summary.entries, "reference"))" }
        return url.lastPathComponent
    }
}
