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
  MarkdownExport.swift        GitHub-flavoured Markdown export
  ExportDate.swift            "EXPORT DATE:" parsing and date ranges
  Reference.swift             BibTeX field parser, LaTeX to text, names, APA 7
  GroundTruth.swift           GroundTruth; WorkspaceWriter (ground truth, annotations)
  NewTest.swift               NewTestDraft, DropRouting, TestCreator
  TextSupport.swift           text reading, list formatting, plurals
Sources/QDVCAutoLitReviewTester/  SwiftUI/AppKit front-end
  AutoLitReviewTesterApp.swift    the App, the window, AppDelegate (⌘F)
  AppModel.swift              all window state and actions
  ContentView.swift           toolbar, split view, status bar, welcome screen
  SidebarView.swift, TablesView.swift, DetailView.swift
  NewTestSheet.swift          the New Test sheet and its drop targets
  AddVariantsSheet.swift      adding variants to an existing multi-RQ test
  GroundTruthSheet.swift      entering a ground truth, with a live APA 7 preview
  ReferenceViews.swift        CopyButton; AttributedString/RTF for references
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
  folder, an export saved there, and what the tester enters in the
  inspector: a ground truth (`ID_ground_truth.bib`) and annotations
  (`…_annotation.md`), both optional and never counted as issues when absent.
- **Annotations save themselves** 0.7 s after typing stops, and at once when
  the app goes to the background or quits or the workspace closes
  (`AppModel.flushAnnotations`). A draft is kept until a scan shows the same
  text on disk; if the file changed elsewhere meanwhile, the file wins.
- **The ground truth's DOI is `doi:10.…`** in the reference, never a URL
  (FILE_FORMAT §5); Copy DOI copies it without the `doi:` prefix.
- **The Markdown export defaults to README.md in the workspace**, and its
  links are relative to the folder it is saved in (`Exporter.relativeLink`).
- The inspector calls a multi-RQ test "Multiple variants"; the tables,
  sidebar and exports keep "Multiple RQs".
- **New Test never changes the originals**: it copies, assembles under a
  hidden name and renames into place, and removes the hidden folder on
  failure. It recounts the BibTeX file at creation time.
- **Add Variants never changes or overwrites anything in the test**
  (`TestCreator.addVariants`): it checks every new top-level name first,
  numbers on from the highest variant, and only works on multi-RQ tests.
- **Older names are accepted with a warning** (FILE_FORMAT §2.3), and the
  standard name wins when both exist. New tests use only standard names.
- **Reference counting** follows FILE_FORMAT §3.2; the CSV and HTML exports and
  the app show the same numbers. Spaces inside citation keys are tolerated on
  purpose (the tool under test writes them); don't "fix" this without asking.
- **Clashing citation keys are information, not issues** (FILE_FORMAT §3.4):
  they never change a status. Each occurrence is shown as `Key (line N)`, the
  line of the entry's `@`.
- **Exports cover every test**, not just what the filters show. All three
  (CSV, HTML, Markdown) carry the same information.
- **Export dates are calendar dates**, with no time zone, so a test's date
  never shifts with the Mac's time zone (FILE_FORMAT §3.5). A missing export
  date is never an issue.
- **Artifacts open in their default apps**; there is no in-app preview.
- Test IDs are A–Z, 0–9 and dashes only, everywhere.

## 4. Tests

`swift test` runs:

- **NamingTests** — ID validation and sanitising, canonical names, natural
  sort, list helpers.
- **BibTeXTests** — special entry types, parenthesised entries, nested braces,
  stray `@`s, key clashes and their line numbers, missing keys, keys with
  spaces, unbalanced files, encodings.
- **ScannerTests** — complete single- and multi-RQ tests, each error and
  warning, older names, numbering problems, stray items, ground truth and
  annotations (reading and writing), the workspace level, name parsing.
- **ReferenceTests** — field parsing (quotes, `#`, macros, comments), LaTeX
  to text, names (particles, suffixes, organisations), APA 7 for each entry
  type, 21+ authors, DOI normalisation, ground-truth problems.
- **ExportTests** — CSV quoting and rows, HTML escaping and structure, the
  Markdown layout and escaping, key clashes, annotations, the ground truth
  and export dates.
- **ExportDateTests** — the date forms, finding dates anywhere in a file,
  impossible dates, range formatting, and a test's range across variants.
- **NewTestTests** — validation messages, planned names, creation (originals
  untouched, recounting, refusal of an existing ID, cleanup on failure),
  optional annotations, adding variants (numbering, never overwriting,
  multi-RQ only) and drop routing.
- **SampleWorkspaceTests** — the expected reading of `sample-workspace/`.

The core also builds and tests with a Linux Swift toolchain, because the
manifest declares the app target only on macOS.

## 5. Roadmap

- Turn a single-RQ test into a multi-RQ one (renaming its files to variant 1)
  so it can take more variants.

- Sentence-case article titles for APA (needs a way to protect proper nouns
  beyond braces).
- Look up a ground truth's BibTeX from its DOI.

- Watch the workspace with FSEvents instead of rescanning on activation.
- Export only the tests shown (filter and search), as an option.
- Check that screenshots are PNGs and reports are PDFs by content, not only
  by name.
- Edit an existing test (add a missing artifact, rename older names to the
  standard ones).
