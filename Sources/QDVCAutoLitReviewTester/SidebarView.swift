import SwiftUI

/// Pane 1: filters, as a native source list with count badges. The badges
/// count tests on the Tests tab and research questions on the other.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            row(.all)
            Section("Status") {
                row(.complete)
                row(.warnings)
                row(.errors)
            }
            Section("Type") {
                row(.single)
                row(.multi)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ filter: TestFilter) -> some View {
        Label(filter.title, systemImage: filter.systemImage)
            .lineLimit(1)
            .badge(model.count(filter))
            .tag(filter)
    }
}
