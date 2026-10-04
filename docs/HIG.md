# Human Interface Guidelines notes

This document records how QDVC Auto Lit Review Tester for macOS lays out its
window and why, with reference to Apple's
[Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
(HIG) and to Apple apps that set the precedent. It follows the same choices as
QDVC Nice Mail and QDVC Bibliotheca for macOS, so the apps feel like a family.
Read it before adding a toolbar item, a button or a tab.

## 1. Navigation: two views of one workspace

The two tabs, **Tests** and **Research Questions**, are two views of the same
data, switched with a segmented control centred in the toolbar and mirrored in
the View menu with ⌘1 and ⌘2. Precedents: **Activity Monitor**, **Calendar**
and Finder's view modes.

Both tabs share one three-column split view (sidebar | list | detail), as
Bibliotheca's tabs do, so the sidebar, toolbar and tab control never move;
only the list changes. Switching tabs keeps the detail pane on the same test.

## 2. The toolbar

Leading: nothing. Centre: the tab control. Trailing, icon-only: **New Test**
(+), **Export** (a menu: CSV or HTML), **Refresh**, then the search field.

- **No window title in the toolbar**, as in Calendar
  (`.windowToolbarStyle(.unified(showsTitle: false))`). The title (the
  workspace folder's name) still names the window in the Window menu, Mission
  Control and VoiceOver.
- **Icon-only buttons with tooltips** that name the shortcut. Every toolbar
  action is also in a menu.

## 3. Panes

- **Sidebar** — a source list of filters with count badges, as in Mail and
  Bibliotheca: All, then Status and Type sections.
- **List** — a native `Table` with sortable columns. A slim status bar under
  it, as in Finder, gives the counts and the workspace's other items.
- **Detail** — a grouped list, one section per research question: the
  question in a serif face (it is quoted prose), the reference count with a
  match symbol, the files, and the issues.

Status is shown by a symbol whose shape differs (check, triangle, octagon) as
well as its colour, with the status as the tooltip and accessibility label, so
colour is never the only cue.

### 3.1 Copying from the inspector

Text in a list row can be selected, but dragging across it also fights the
row selection, so everything worth copying has its own button, as in
Passwords and Contacts: a copy button beside each research question (and Copy
in its context menu), Copy All Research Questions in the test header for
multi-RQ tests, and Copy Reference and Copy DOI under the ground truth. The
button's symbol turns into a check mark for a moment to confirm the copy.
Each has a menu item and shortcut in the Test menu.

### 3.2 Ground truth and annotations

The ground truth is a section of its own near the top of the inspector,
because it belongs to the whole test: the APA 7 reference in the same serif
face as the research questions, then Copy Reference, Copy DOI and Edit…. It
is entered in a sheet (a BibTeX editor with a live APA 7 preview and the DOI
it found), since it is pasted rather than typed.

Each research question has an annotation field just under its text. There is
no Save button: it saves itself a moment after typing stops, as Notes and
Reminders do.

## 4. Opening files

Artifacts are opened in their default apps (Preview, the browser, a BibTeX
editor), never previewed inside the app. Double-click opens, as in Finder;
**⌘↓** is Finder's Open shortcut; right-click offers Reveal in Finder and Copy
Path. Double-clicking a test opens its folder; double-clicking a research
question opens its report PDF.

## 5. The New Test sheet

A sheet, because it creates one thing and then closes, as in Bibliotheca's New
Work. It uses a grouped form (System Settings style): the ID and type at the
top, then one section per research question, each with a question field and
five drop targets. Drop targets highlight when a file is dragged over them and
show the chosen file's name (and, for BibTeX, the number of references).

- The ID field capitalises lowercase letters as you type and refuses anything
  else not allowed, with a beep and a note, as text fields do when a formatter
  rejects a character.
- **Create Test** is the default button and stays disabled until everything is
  there; the footer says what is still missing, one item at a time.
- "Files to be created" previews the folder, left-aligned like a file list.
- Each research question has an optional annotation field under the question.
- **Add Variants** reuses the same sheet layout (one section per new variant)
  without the ID and type, and says in its first line which variants the test
  already has and where the numbering continues.

## 6. Shortcuts

Standard where macOS has a standard (⌘N, ⌘O, ⌘F, ⌘R, ⌘↓, ⌘,); ⇧⌘W closes the
workspace, as in the other QDVC apps; ⇧⌘E and ⌥⇧⌘E export.
