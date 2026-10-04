import SwiftUI
import AutoLitReviewCore

/// Test → Add Variants… (⌥⌘N): more research questions for an existing
/// multi-RQ test, numbered on from its highest variant. Works like the New
/// Test sheet: type each question (and, optionally, an annotation) and drop
/// its files; they are copied in under the standard names, and nothing that
/// is already in the test is changed.
struct AddVariantsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let test: TestRun

    @State private var draft: AddVariantsDraft
    @State private var dropNote: String?
    @State private var addProblem: String?

    init(test: TestRun) {
        self.test = test
        _draft = State(initialValue: AddVariantsDraft(test: test))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Variants to \(test.id)")
                    .font(.title2.weight(.semibold))
                Text(existingSummary + " The new ones are numbered from \(draft.firstVariant). Drop each variant\u{2019}s files on it, or use Choose\u{2026}; they are copied in, and nothing already in the test is changed.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 6)

            Form {
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
                        Label("Add Another Variant", systemImage: "plus")
                    }
                }
                Section {
                    DisclosureGroup("Files to be created") {
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
            .formStyle(.grouped)

            Divider()
            HStack(alignment: .center, spacing: 12) {
                footerMessage
                Spacer(minLength: 12)
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.questions.count == 1 ? "Add Variant" : "Add \(draft.questions.count) Variants") {
                    addProblem = model.addVariants(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!problems.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 660, height: 680)
        .onChange(of: draft) { addProblem = nil }
    }

    @ViewBuilder
    private var footerMessage: some View {
        if let addProblem {
            Label(addProblem, systemImage: "exclamationmark.triangle.fill")
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
            Label("Ready to add", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var problems: [String] { draft.problems() }

    private var existingSummary: String {
        let numbers = test.questions.compactMap(\.variant).map(String.init)
        return numbers.count == 1
            ? "\(test.id) has variant \(numbers[0])."
            : "\(test.id) has variants \(TextSupport.list(numbers))."
    }

    private func variantNumber(of id: UUID) -> Int {
        draft.variant(at: draft.questions.firstIndex { $0.id == id } ?? 0)
    }
}
