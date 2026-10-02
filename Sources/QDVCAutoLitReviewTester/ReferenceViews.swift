import AppKit
import SwiftUI
import AutoLitReviewCore

extension FormattedReference {
    /// For SwiftUI `Text`: italic runs marked as emphasised.
    var attributed: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var run = AttributedString(segment.text)
            if segment.italic { run.inlinePresentationIntent = .emphasized }
            result += run
        }
        return result
    }

    /// For the pasteboard's RTF: Times New Roman 12 pt with real italics, the
    /// usual reference-list face.
    var attributedString: NSAttributedString {
        let base = NSFont(name: "Times New Roman", size: 12) ?? NSFont.systemFont(ofSize: 12)
        let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        let result = NSMutableAttributedString()
        for segment in segments {
            result.append(NSAttributedString(string: segment.text, attributes: [.font: segment.italic ? italic : base]))
        }
        return result
    }
}

/// A copy button that shows a check mark for a moment after copying.
struct CopyButton: View {
    let title: String
    var iconOnly = false
    let action: () -> Void

    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        } label: {
            if iconOnly {
                Label(title, systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            } else {
                Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .help(title)
        .accessibilityLabel(title)
    }
}
