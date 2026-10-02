# QDVC Auto Lit Review Tester for macOS — Maintenance Guide

## 1. Layout

```
Package.swift                 SwiftPM manifest (app target on macOS only)
Sources/AutoLitReviewCore/    Foundation-only model layer, unit-tested
  Models.swift                TestRun, ResearchQuestion, Issue, Status, ArtifactKind…
  Naming.swift                test IDs, canonical names, natural sort, date stamps
  BibTeX.swift                the reference counter
  Scanner.swift               WorkspaceScanner: reads a workspace and checks it
  Export.swift                CSV and HTML exports
  NewTest.swift               NewTestDraft, DropRouting, TestCreator
  TextSupport.swift           text reading, list formatting, plurals
Sources/QDVCAutoLitReviewTester/  SwiftUI/AppKit front-end
  AutoLitReviewTesterApp.swift    the App, the window, AppDelegate (⌘F)
  AppModel.swift              all window state and actions
  ContentView.swift           toolbar, split view, status bar, welcome screen
  SidebarView.swift, TablesView.swift, DetailView.swift
  NewTestSheet.swift          the New Test sheet and its drop targets
  Commands.swift              menu-bar commands
  StatusViews.swift, Platform.swift, Prefs.swift, SettingsView.swift
Tests/AutoLitReviewCoreTests/ XCTest suites
Resources/                    Info.plist, AppIcon.svg, AppIcon.icns
scripts/build-app.sh          builds and ad-hoc signs the .app
tools/make_icon.py            regenerates the icon
tools/make_sample_workspace.py  regenerates sample-workspace/
sample-workspace/             example test runs, one per kind of result
```

### 1.1 App icon

`tools/make_icon.py` writes `Resources/AppIcon.svg` and renders every size of
`Resources/AppIcon.icns` from it with `rsvg-convert`. It uses Apple's macOS
template geometry (824 px tile with continuous corners on a 1024 px canvas,
the template drop shadow) and the Liquid Glass treatment of the other QDVC
icons. Run it after changing the design; `--preview` also writes
`build/icon-preview.png`.

## 2. Modules

**AutoLitReviewCore** has no UI code and builds on Linux too, so its tests can
run anywhere. `WorkspaceScanner.scan` returns a `WorkspaceScan` of value types;
it only reads, and never throws for problems inside a test (those become
`Issue`s). `TestScanner` (private) does the per-folder work: it parses each
name into `(variant, rest)`, collects candidates per variant and artifact,
then builds one `ResearchQuestion` per variant and runs the checks in
docs/FILE_FORMAT.md §3.

**QDVCAutoLitReviewTester** keeps all state in `AppModel` (`@Observable`,
main actor). Scans run on a detached task; a generation counter makes sure
only the latest result is applied. The tables show `TestRow` and
`QuestionRow` snapshots rebuilt by `refreshRows()` after a scan, a filter or a
sort change. The detail pane and the Test menu act on `focusedTest` and
`focusedQuestion`.

## 3. Behaviour that must be preserved

- **Scanning never writes.** The only writes to a workspace are New Test's
  folder and an export saved there.
- **New Test never changes the originals**: it copies, assembles under a
  hidden name and renames into place, and removes the hidden folder on
  failure. It recounts the BibTeX file at creation time.
- **Older names are accepted with a warning** (FILE_FORMAT §2.3), and the
  standard name wins when both exist. New tests use only standard names.
- **Reference counting** follows FILE_FORMAT §3.2; the CSV and HTML exports and
  the app show the same numbers. Spaces inside citation keys are tolerated on
  purpose (the tool under test writes them); don't "fix" this without asking.
- **Exports cover every test**, not just what the filters show.
- **Artifacts open in their default apps**; there is no in-app preview.
- Test IDs are A–Z, 0–9 and dashes only, everywhere.

## 4. Tests

`swift test` runs:

- **NamingTests** — ID validation and sanitising, canonical names, natural
  sort, list helpers.
- **BibTeXTests** — special entry types, parenthesised entries, nested braces,
  stray `@`s, duplicate and missing keys, keys with spaces, unbalanced files,
  encodings.
- **ScannerTests** — complete single- and multi-RQ tests, each error and
  warning, older names, numbering problems, stray items, the workspace level,
  name parsing.
- **ExportTests** — CSV quoting and rows, HTML escaping and structure.
- **NewTestTests** — validation messages, planned names, creation (originals
  untouched, recounting, refusal of an existing ID, cleanup on failure) and
  drop routing.
- **SampleWorkspaceTests** — the expected reading of `sample-workspace/`.

The core also builds and tests with a Linux Swift toolchain, because the
manifest declares the app target only on macOS.

## 5. Roadmap

- Watch the workspace with FSEvents instead of rescanning on activation.
- Export only the tests shown (filter and search), as an option.
- Check that screenshots are PNGs and reports are PDFs by content, not only
  by name.
- Edit an existing test (add a missing artifact, rename older names to the
  standard ones).
