import AppKit
import SwiftUI
import AutoLitReviewCore

/// Enter or edit a test's ground truth: one BibTeX entry for a published
/// paper asking the same research questions. The APA 7 preview updates as
/// you type; saving writes `ID_ground_truth.bib` in the test folder.
struct GroundTruthSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let testID: String
    let hasExisting: Bool

    @State private var text: String
    @State private var saveProblem: String?

    init(testID: String, initialText: String, hasExisting: Bool) {
        self.testID = testID
        self.hasExisting = hasExisting
        _text = State(initialValue: initialText)
    }

    private var preview: GroundTruth { GroundTruth(source: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ground Truth for \(testID)")
                .font(.title2.weight(.semibold))
            Text("Paste the BibTeX entry of a published paper that asks the same research questions, or drop a .bib file here. It is kept in \(Naming.groundTruthFileName(testID: testID)) in the test folder.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .frame(minHeight: 200)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first, let dropped = try? TextSupport.readText(url) else { return false }
                    text = dropped
                    return true
                }

            GroupBox("APA 7 preview") {
                VStack(alignment: .leading, spacing: 8) {
                    if text.trimmed.isEmpty {
                        Text("The formatted reference appears here.")
                            .foregroundStyle(.secondary)
                    } else if let reference = preview.reference {
                        Text(reference.attributed)
                            .font(.system(.body, design: .serif))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text("DOI").foregroundStyle(.secondary)
                            Text(preview.doi ?? "none in the entry")
                                .textSelection(.enabled)
                                .foregroundStyle(preview.doi == nil ? Color.secondary : Color.primary)
                        }
                        .font(.callout)
                    }
                    if !text.trimmed.isEmpty, let problem = preview.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            if let saveProblem {
                Label(saveProblem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                if hasExisting {
                    Button("Remove Ground Truth", role: .destructive) {
                        saveProblem = model.saveGroundTruth("", for: testID)
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveProblem = model.saveGroundTruth(text, for: testID)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.entryCount != 1)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}
