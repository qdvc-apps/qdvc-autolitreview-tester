import SwiftUI
import AutoLitReviewCore

extension Status {
    var systemImage: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .warnings: return "exclamationmark.triangle.fill"
        case .errors: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .complete: return .green
        case .warnings: return .orange
        case .errors: return .red
        }
    }
}

extension TestKind {
    /// How the inspector names the kind: "Single RQ" or "Multiple variants".
    var inspectorTitle: String {
        switch self {
        case .single: return "Single RQ"
        case .multi: return "Multiple variants"
        }
    }
}

extension Severity {
    var systemImage: String { self == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill" }
    var color: Color { self == .error ? .red : .orange }
    var title: String { self == .error ? "Error" : "Warning" }
}

/// A coloured status symbol, with the status as its accessibility label and
/// tooltip (colour is never the only cue).
struct StatusIcon: View {
    let status: Status

    var body: some View {
        Image(systemName: status.systemImage)
            .foregroundStyle(status.color)
            .help(status.title)
            .accessibilityLabel(status.title)
    }
}

extension ArtifactKind {
    var systemImage: String {
        switch self {
        case .queryAsked: return "photo"
        case .responseReceived: return "photo.on.rectangle"
        case .rqText: return "text.quote"
        case .references: return "books.vertical"
        case .report: return "doc.richtext"
        case .reportDOM: return "chevron.left.forwardslash.chevron.right"
        }
    }
}
