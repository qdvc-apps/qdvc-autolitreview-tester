import AppKit
import SwiftUI

@main
struct AutoLitReviewTesterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // A single main window, like the other QDVC apps.
        Window("QDVC Auto Lit Review Tester", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 820, minHeight: 480)
                .onAppear { model.startUp() }
        }
        .defaultSize(width: 1240, height: 720)
        // No window title in the toolbar (as in Calendar), leaving room for
        // the tabs and actions; it still names the window in the Window menu,
        // Mission Control and VoiceOver (docs/HIG.md §2).
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            TesterCommands(model: model)
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // ⌘F jumps to the toolbar search field. In a sheet (New Test) there
        // is none, so the key goes on to the text fields as usual.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" else { return event }
            return Platform.focusSearchField(in: event.window) ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
