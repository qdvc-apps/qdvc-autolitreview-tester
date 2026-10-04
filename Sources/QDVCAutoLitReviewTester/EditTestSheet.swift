import AppKit
import SwiftUI
import AutoLitReviewCore

/// Test → Supply Missing Artifacts… / Edit Test… (⌥⌘E): the data entry form
/// again, for an existing test. What the test already has is shown ticked and
/// left as it is; each missing artifact is a drop target, a missing research
/// question can be typed, and annotations can be edited. Saving copies the
/// new files in under the standard names, and it is fine to save with some
/// artifacts still missing.
struct EditTestSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let test: TestRun

    @State private var draft: CompletionDraft
    @State private var dropNote: String?
    @State private var saveProblem: String?

    init(test: TestRun) {
        self.test = test
        _draft = State(initialValue: CompletionDraft(test: test))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.hasMissing ? "Supply Missing Artifacts for \(test.id)" : "Edit \(test.id)")
                    .font(.title2.weight(.semibold))
                Text(intro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 6)

            Form {
                ForEach($draft.questions) { $question in
                    Section {
                        CompletionQuestionEditor(question: $question, testID: test.id, onNote: { dropNote = $0 })
                    } header: {
                        HStack {
                            Text(question.variant.map { "Variant \($0)" } ?? "Research Question")
                            Spacer()
                            if question.missing.isEmpty {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.callout)
                            } else {
                                Text("\(question.missing.count) missing")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        }
                    }
                }
                if !draft.plannedFiles().isEmpty {
                    Section {
                        DisclosureGroup("Files to be added") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(draft.plannedFiles().map(\.relativePath), id: \.self) { path in
                                    Text("\(test.id)/\(path)")
                                        .font(.system(.caption, design: .monospaced))
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                Button("Save") {
                    saveProblem = model.saveCompletion(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.hasChanges || !draft.problems.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 660, height: 720)
        .onChange(of: draft) { saveProblem = nil }
    }

    private var intro: String {
        draft.hasMissing
            ? "Drop the missing files on their slots (several at once is fine) or use Choose\u{2026}. They are copied in under the standard names; the files already in the test are kept as they are. You can save with some still missing."
            : "Everything is in place. You can edit the annotations here."
    }

    @ViewBuilder
    private var footerMessage: some View {
        if let saveProblem {
            Label(saveProblem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        } else if let first = draft.problems.first {
            Label(first, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
        } else if let dropNote {
            Label(dropNote, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .lineLimit(3)
        } else if !draft.hasChanges {
            Label(draft.hasMissing ? "Drop or choose the missing files" : "No changes", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        } else if let first = draft.stillMissingSummary.first {
            let more = draft.stillMissingSummary.count > 1 ? " (and more)" : ""
            Label("Still missing after saving: " + first + more, systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .help(draft.stillMissingSummary.joined(separator: "\n"))
        } else {
            Label("Ready to save; nothing will be missing", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

/// One research question of an existing test: its text (typed only if it is
/// missing), its annotation, and a row per artifact, ticked if the test has
/// it or a drop target if not.
private struct CompletionQuestionEditor: View {
    @Binding var question: CompletionQuestion
    let testID: String
    let onNote: (String?) -> Void

    var body: some View {
        if let text = question.existingQuestion {
            Text(text)
                .font(.system(.body, design: .serif))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            TextField("Question", text: $question.input.text,
                      prompt: Text("Missing: the research question exactly as it was asked"), axis: .vertical)
                .lineLimit(2...8)
                .dropDestination(for: URL.self) { urls, _ in handleDrop(urls, preferring: nil) }
        }
        TextField("Annotation", text: $question.input.annotation,
                  prompt: Text("Optional: a brief note about this research question"), axis: .vertical)
            .lineLimit(1...5)
        ForEach(ArtifactKind.suppliedFiles) { kind in
            if let path = question.existing[kind] {
                ExistingArtifactRow(kind: kind, path: path)
            } else {
                FileSlotRow(kind: kind,
                            url: question.input.files[kind],
                            summary: kind == .references ? question.input.referenceSummary : nil,
                            error: kind == .references ? question.input.referenceError : nil,
                            onDrop: { urls in handleDrop(urls, preferring: kind) },
                            onChoose: { choose(kind) },
                            onClear: { question.input.setFile(nil, for: kind) })
            }
        }
    }

    /// Routes dropped files to the missing slots; a file for an artifact the
    /// test already has is refused, so nothing is replaced.
    private func handleDrop(_ urls: [URL], preferring kind: ArtifactKind?) -> Bool {
        let files = urls.filter { !Platform.isDirectory($0) }
        var current = question.input.files
        for existing in question.existing.keys { current[existing] = URL(fileURLWithPath: "/") }
        let result = DropRouting.route(files, preferring: kind, current: current)
        var refused: [URL] = []
        var used = false
        for assignment in result.assignments {
            if question.existing[assignment.kind] != nil {
                refused.append(assignment.url)
            } else {
                question.input.setFile(assignment.url, for: assignment.kind)
                used = true
            }
        }
        if let textURL = result.questionText, question.existingQuestion == nil,
           let text = try? TextSupport.readText(textURL) {
            question.input.text = text.trimmed
            used = true
        }
        let unused = result.rejected + refused + urls.filter { Platform.isDirectory($0) }
        if unused.isEmpty {
            onNote(nil)
        } else {
            NSSound.beep()
            onNote("Not used: " + TextSupport.list(unused.map(\.lastPathComponent), limit: 3)
                   + ". Only missing artifacts can be added; the test\u{2019}s files are kept as they are.")
        }
        return used
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
            question.input.setFile(url, for: kind)
            onNote(nil)
        }
    }
}

/// An artifact the test already has: ticked, with its file name.
private struct ExistingArtifactRow: View {
    let kind: ArtifactKind
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Image(systemName: kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text("In the test")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}
