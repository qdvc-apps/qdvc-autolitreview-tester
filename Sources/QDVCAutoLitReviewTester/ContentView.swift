import AppKit
import SwiftUI
import AutoLitReviewCore

/// The main window. As in Activity Monitor, a segmented control centred in
/// the toolbar switches tabs (⌘1, ⌘2). Both tabs share one three-column
/// split view (filters | list | detail), so the window keeps its shape as
/// you switch; see docs/HIG.md. The welcome screen shows when no workspace
/// is open.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasWorkspace {
                MainSplitView()
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("View", selection: tabBinding) {
                                ForEach(AppTab.allCases) { tab in
                                    Text(tab.title).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .help("Switch between Tests and Research Questions (\u{2318}1, \u{2318}2)")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                model.beginNewTest()
                            } label: {
                                Label("New Test", systemImage: "plus")
                            }
                            .help("Set up a new test folder (\u{2318}N)")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button("Export as CSV\u{2026}") { model.export(.csv) }
                                Button("Export as HTML\u{2026}") { model.export(.html) }
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .help("Export every test and research question as CSV or HTML")
                            .disabled(model.scan == nil)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                model.refresh()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .help("Scan the workspace again (\u{2318}R)")
                        }
                    }
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(model.windowTitle)
        .overlay {
            if model.isLoading {
                ProgressView("Reading the workspace\u{2026}")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .newTest:
                NewTestSheet()
                    .environment(model)
            case .groundTruth(let testID):
                GroundTruthSheet(testID: testID,
                                 initialText: model.scan?.test(testID)?.groundTruth?.source ?? "",
                                 hasExisting: model.scan?.test(testID)?.groundTruth != nil)
                    .environment(model)
            }
        }
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil },
                                    set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.appBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            model.flushAnnotations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.flushAnnotations()
        }
    }

    /// Switching tabs through the picker also keeps the selection in step.
    private var tabBinding: Binding<AppTab> {
        Binding(get: { model.currentTab },
                set: { tab in
                    let old = model.currentTab
                    model.currentTab = tab
                    if old != tab { model.tabChanged(from: old) }
                })
    }
}

/// The one split view behind both tabs. Keeping a single instance keeps the
/// sidebar width, the toolbar and the centred tab control steady.
struct MainSplitView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } content: {
            Group {
                switch model.currentTab {
                case .tests: TestsTableView()
                case .questions: QuestionsTableView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
            .navigationSplitViewColumnWidth(min: 420, ideal: 640)
        } detail: {
            DetailView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
        .searchable(text: $model.searchText, placement: .toolbar,
                    prompt: Text(model.currentTab == .tests ? "Filter tests" : "Filter research questions"))
        .onChange(of: model.searchText) { model.refreshRows() }
        .onChange(of: model.sidebarSelection) { model.refreshRows() }
    }
}

/// A slim bar under the list, as in Finder: counts, and the items in the
/// workspace that aren't tests.
struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text(model.statusLine)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let other = model.scan?.otherItems, !other.isEmpty {
                    Label(TextSupport.plural(other.count, "other item"), systemImage: "questionmark.folder")
                        .labelStyle(.titleAndIcon)
                        .help("Not test folders (a test folder\u{2019}s name uses only A\u{2013}Z, 0\u{2013}9 and dashes): "
                              + TextSupport.list(other, limit: 12))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }
}

/// Shown when no workspace is open.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("QDVC Auto Lit Review Tester")
                .font(.largeTitle.weight(.semibold))
            Text("Open the workspace folder that holds your test runs \u{2014} one folder per test, named like ABCD-123 \u{2014} to check them, browse the research questions and reference counts, and set up new tests.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if !model.recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(Array(model.recentWorkspaces.prefix(5)), id: \.self) { path in
                        Button((path as NSString).abbreviatingWithTildeInPath) {
                            model.openWorkspace(URL(fileURLWithPath: path, isDirectory: true))
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: Platform.isDirectory) else { return false }
            model.openWorkspace(folder)
            return true
        }
    }
}
