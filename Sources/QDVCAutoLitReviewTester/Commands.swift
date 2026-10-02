import AppKit
import SwiftUI
import AutoLitReviewCore

extension AppTab {
    /// ⌘1 and ⌘2, in tab order.
    var shortcut: KeyEquivalent { self == .tests ? "1" : "2" }
}

/// Menu-bar commands. Standard items (Edit, Window, Help, Settings…, Quit,
/// About) come from the system; these add the workspace, view and test
/// actions.
struct TesterCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Test\u{2026}") { model.beginNewTest() }
                .keyboardShortcut("n")
                .disabled(!model.hasWorkspace)
            Divider()
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentWorkspaces, id: \.self) { path in
                    Button((path as NSString).abbreviatingWithTildeInPath) {
                        model.openWorkspace(URL(fileURLWithPath: path, isDirectory: true))
                    }
                }
                if !model.recentWorkspaces.isEmpty {
                    Divider()
                    Button("Clear Menu") { model.clearRecents() }
                }
            }
            Button("Reveal Workspace in Finder") { model.revealWorkspace() }
                .disabled(!model.hasWorkspace)
            Divider()
            Button("Export as CSV\u{2026}") { model.export(.csv) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.scan == nil)
            Button("Export as HTML\u{2026}") { model.export(.html) }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
                .disabled(model.scan == nil)
            Divider()
            Button("Close Workspace") { model.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!model.hasWorkspace)
        }

        CommandGroup(after: .toolbar) {
            ForEach(AppTab.allCases) { tab in
                Button(tab.title) {
                    let old = model.currentTab
                    model.currentTab = tab
                    if old != tab { model.tabChanged(from: old) }
                }
                .keyboardShortcut(tab.shortcut)
                .disabled(!model.hasWorkspace)
            }
            Divider()
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(!model.hasWorkspace)
            Divider()
        }

        CommandMenu("Test") {
            let question = model.focusedQuestion
            Button("Open Report PDF") { model.open(.report, of: question) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(question?.file(.report) == nil)
            Button("Open Report DOM") { model.open(.reportDOM, of: question) }
                .disabled(question?.file(.reportDOM) == nil)
            Button("Open References") { model.open(.references, of: question) }
                .disabled(question?.file(.references) == nil)
            Button("Open Query Folder") { model.openQueryFolder(question) }
                .disabled(question?.file(.rqText) == nil && question?.file(.queryAsked) == nil
                          && question?.file(.responseReceived) == nil)
            Divider()
            Button("Copy Research Question") { model.copyQuestion(question) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(question?.question == nil)
            Button("Reveal in Finder") { model.revealFocused() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.focusedTest == nil)
        }
    }
}
