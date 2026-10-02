import SwiftUI

/// Settings (⌘,). Both preferences are read when they're needed, so a
/// change takes effect straight away.
struct SettingsView: View {
    @AppStorage(Prefs.Key.reopenLast) private var reopenLast = true
    @AppStorage(Prefs.Key.refreshOnActivate) private var refreshOnActivate = true

    var body: some View {
        Form {
            Toggle("Reopen the last workspace at launch", isOn: $reopenLast)
            Toggle("Refresh when the app comes to the front", isOn: $refreshOnActivate)
            Text("Picks up test folders added or changed in Finder while you were in another app.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
