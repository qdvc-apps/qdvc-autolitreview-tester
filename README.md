# QDVC Auto Lit Review Tester for macOS

A native SwiftUI app for macOS 14 (Sonoma) and later, for testers of an
automated literature review tool. Open a **workspace** (a folder holding one
folder per test run, named like `ABCD-123`) and the app:

- works out whether each test asked one research question or several
  (**variants**), and checks that every artifact is there: the two
  screenshots, the research question, the BibTeX references, the report PDF
  and the report DOM;
- counts the entries in every `.bib` file and checks them against the count in
  its name (`ABCD-123_references_n293.bib` must hold 293 references);
- optionally, as set in the workspace's `workspace.yml`, checks each report
  DOM for the research question's exact text and for "Show all N
  references", warning when either is missing;
- lists every test with its research questions, reference counts and **date**
  (the `EXPORT DATE` in its BibTeX files, or their range across variants),
  and opens any artifact in its default app with a double-click;
- exports the sheet of tests, research questions and reference counts as
  **CSV**, a **self-contained single-page HTML** report, or **Markdown**
  laid out for reading on GitHub or a similar Git host (saved as the
  workspace's `README.md` by default, with links to every test's files);
- sets up a **new test**: type the ID and the research questions, drop the
  files, and it copies them into a new folder under the standard names.
  The originals are never moved or changed.

The workspace format and every check are described in
[docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).

## What it does

The window has two tabs, switched with the segmented control in the toolbar
(⌘1, ⌘2), as in Activity Monitor. Both share three panes: filters, a list and
a detail pane.

- **Sidebar** — All, Complete, With Warnings, With Errors, Single RQ and
  Multiple RQs, with counts. On the Research Questions tab the status filters
  apply to each research question's row.
- **Tests** — one row per test: status, test ID, type, number of research
  questions, references per research question, the first question, and the
  number of issues. Click a column header to sort. Double-click a row to open
  the test folder in Finder; right-click for the artifacts of each variant.
- **Research Questions** — one row per research question (the same sheet the
  export writes): test ID, variant, question, references found, the count in
  the file name, whether they match, the annotation and the number of key
  clashes. The Tests list also shows each test's ground truth. Double-click a row to open its
  report PDF.
- **Detail pane** (the inspector) — the selected test: its **ground truth**
  and each research question's text, **annotation**, reference count, any
  clashing citation keys (with line numbers), files and issues. Every
  research question has a copy button beside it, and a multi-RQ test has
  **Copy All Research Questions**.
- **Ground truth** — for each test, the BibTeX entry of a published paper
  asking the same research questions (Edit… or Add… in the inspector, ⇧⌘G).
  It is shown as an APA 7 reference with the DOI written `doi:10.1234/abcd`,
  and **Copy Reference** (rich text, so italics survive a paste) or **Copy
  DOI** copy it (the DOI alone, without the `doi:` prefix).
- **Annotations** — a brief note on each research question, typed in the
  inspector and saved automatically. Double-click a file (or select it
  and press ⌘↓) to open it in its default app; right-click to reveal it in
  Finder or copy its path.
- **Search** (⌘F, in the toolbar) filters by test ID or research question.
- **Export** (the toolbar's share button; ⇧⌘E for CSV, ⌥⇧⌘E for HTML,
  ⌃⇧⌘E for Markdown) writes every test in the workspace.
- **New Test** (⌘N, or the + button) — enter the test ID (A–Z, 0–9 and dashes;
  lowercase letters are capitalised as you type, spaces are refused), choose
  Single RQ or Multiple RQs, type each research question and drop its five
  files. Several files can be dropped at once anywhere on a research question
  and each goes to the right slot; a dropped `.md` or `.txt` file fills in the
  question. The BibTeX file's references are counted to name it. **Create
  Test** is enabled once everything is there. Each research question can
  also have an optional annotation.
- **Add Variants** (⌥⌘N, or the button in the inspector's header) adds
  research questions to an existing multi-RQ test, numbered on from its
  highest variant, in the same way: type the question (and an optional
  annotation) and drop the files. Nothing already in the test is changed.

Problems are **errors** (something is missing or wrong, such as a count that
doesn't match the file name) or **warnings** (worth a look, such as a file
named the older way or a stray file). **Clashing citation keys** (separate
references given the same key) are listed for information, as in
`Smith2025 (line 94) and Smith2025 (line 255)`, without affecting the status.

**DOM checks** are turned on in a `workspace.yml` at the top of the
workspace:

```yaml
dom_checks:
  rq_text_string_check: True
  all_n_references_check: True
```

The status bar shows which checks are on (or what's wrong with the file), the
inspector shows each research question's results, and a failed check is a
warning. See [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) §1.1 and §3.6.

**View → Refresh** (⌘R) scans the workspace again; by default the app also
does so whenever it comes to the front (Settings, ⌘,).

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16 or later (free from the Mac App Store). The Command Line Tools
  alone can build and run the app, but `swift test` needs full Xcode.
- No paid Apple Developer account.

## Build and run

From the repository root:

```sh
swift run                                           # build and launch (debug)
swift run QDVCAutoLitReviewTester sample-workspace  # …opening the sample workspace
swift test                                          # run the unit tests
scripts/build-app.sh                                # build "build/QDVC Auto Lit Review Tester.app" (release)
scripts/build-app.sh --install                      # …and copy it to ~/Applications
```

Or open the repository folder in Xcode (File → Open…, choose the folder that
contains `Package.swift`), pick the **QDVCAutoLitReviewTester** scheme and
press ⌘R. Xcode may ask for a team: choose **None** / **Sign to Run Locally**.

A ready-made `sample-workspace/` shows every kind of result: complete
single- and multi-RQ tests, a count mismatch, a missing file, older names and
a gap in the variant numbering. `tools/make_sample_workspace.py` regenerates
it and describes each case.

## Signing without a paid account

`scripts/build-app.sh` signs the app **ad hoc** (`codesign --sign -`). That is
all macOS needs to run an app on the Mac that built it — no account, no
certificate, no notarisation.

A paid Developer ID is only needed to *distribute* the app so that it opens on
other Macs without a warning. If you give the ad-hoc-signed app to someone
else, macOS will block the first launch; they can allow it once in
**System Settings → Privacy & Security → Open Anyway**, or remove the
quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/QDVC Auto Lit Review Tester.app"
```

Because an ad-hoc signature changes with every build, macOS may ask again for
permission to access folders such as Documents, Desktop or iCloud Drive after
you rebuild. That is expected.

## App icon

The icon, a frosted-glass report page under a magnifying glass holding a
check mark, on a sea-glass teal tile, is generated by `tools/make_icon.py`,
which follows Apple's macOS icon template; see
[docs/MAINTENANCE.md](docs/MAINTENANCE.md) §1.1. It appears in the `.app`
built by `scripts/build-app.sh`, but not when you use `swift run`.

## Where things are stored

- Test runs: only in the workspace folder you open. Scanning only reads. The
  app writes there only when you ask: a new test folder from New Test, a
  ground truth (`ID_ground_truth.bib`), annotations (`…_annotation.md`) and
  an export, if you save it there.
- Preferences and recent workspaces: the standard macOS defaults domain
  (`defaults read org.qdvc.autolitreviewtester`).
- Exports: wherever you choose in the Save panel.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘1, ⌘2 | Tests, Research Questions |
| ⌘N | New test |
| ⌥⌘N | Add variants to the selected multi-RQ test |
| ⌘O | Open workspace |
| ⇧⌘W | Close workspace |
| ⌘F | Search |
| ⌘R | Refresh |
| ⇧⌘E / ⌥⇧⌘E / ⌃⇧⌘E | Export as CSV / HTML / Markdown |
| ⌘↓ | Open the report PDF of the selected research question |
| ⇧⌘C | Copy the selected research question |
| ⌥⇧⌘C | Copy all of the test's research questions |
| ⇧⌘G | Add or edit the test's ground truth |
| ⌃⌘C / ⌃⌥⌘C | Copy the ground truth's APA 7 reference / DOI |
| ⌥⌘R | Reveal the selected file or test in Finder |
| ⌘, | Settings |
| Double-click | Tests: open the folder; Research Questions: open the report PDF; detail pane: open the file |

## Documentation

- **[docs/FILE_FORMAT.md](docs/FILE_FORMAT.md)** — the workspace layout, file
  names, the checks and their messages, reference counting, ground truth and
  annotations, APA 7 formatting and the exports.
- **[docs/HIG.md](docs/HIG.md)** — the window layout and its precedents in
  Apple's Human Interface Guidelines and apps.
- **[docs/MAINTENANCE.md](docs/MAINTENANCE.md)** — architecture, modules,
  behaviour to preserve, tests and the roadmap.

## License

No license has been chosen yet. Add a `LICENSE` file before publishing.
