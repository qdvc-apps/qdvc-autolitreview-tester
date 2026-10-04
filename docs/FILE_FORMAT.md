# Workspace format

This document describes the folders and files QDVC Auto Lit Review Tester
reads and writes, the checks it makes, and the two export formats. The rules
live in `Sources/AutoLitReviewCore` (`Naming.swift`, `Scanner.swift`,
`BibTeX.swift`, `Export.swift`, `NewTest.swift`); keep this document in step
with them.

## 1. The workspace

A workspace is any folder. Every folder in it whose name is one or more of
**A–Z, 0–9 and dashes** (`ABCD-123`, `SLR-7`, `2026-01`) is a **test**, and
its name is the **test ID**. Anything else at the top level (files, folders
with lowercase letters, spaces or underscores) is listed in the status bar as
an "other item" but is not a problem: exports often end up there. Hidden items
(names starting with a dot, such as `.DS_Store`) are ignored everywhere.

## 2. A test folder

### 2.1 Single research question

```
ABCD-123/
  ABCD-123_query/
    ABCD-123_query_asked.png         screenshot of the query as asked
    ABCD-123_response_received.png   screenshot of the response
    ABCD-123_RQ_asked.md             the research question, as plain text
  ABCD-123_references_n293.bib       the references; 293 = how many
  ABCD-123_report.pdf                the generated literature review
  ABCD-123_report_DOM.html           the review page's DOM
```

### 2.2 Several research questions (variants)

Each variant has the same six artifacts, numbered from 1:

```
ABCD-123/
  ABCD-123_query_variant1/
    ABCD-123_variant1_query_asked.png
    ABCD-123_variant1_response_received.png
    ABCD-123_variant1_RQ_asked.md
  ABCD-123_query_variant2/
    …
  ABCD-123_variant1_references_n67.bib
  ABCD-123_variant1_report.pdf
  ABCD-123_variant1_report_DOM.html
  ABCD-123_variant2_references_n23.bib
  …
```

A test is **multi-RQ** as soon as any item in it names a variant; otherwise
it is single-RQ. Every variant that appears anywhere (a query folder or any
artifact) gets a row, so a variant with only some files is reported as
incomplete rather than missed.

### 2.3 Older names

These forms are accepted, with a warning naming the standard form:

| Older form | Standard form |
| --- | --- |
| `ABCD-123_variant2/` (query folder) | `ABCD-123_query_variant2/` |
| `ABCD-123_query_variant2_references_n23.bib` (and other top-level files) | `ABCD-123_variant2_references_n23.bib` |
| `ABCD-123_query_variant2_query_asked.png` (inside a query folder) | `ABCD-123_variant2_query_asked.png` |
| `variant02` (leading zeros) | `variant2` |

When both forms of the same artifact exist, the standard one is used and the
duplicate is reported. New tests are always written with the standard names.

### 2.4 Contents

- **`RQ_asked.md`** is plain text, not Markdown. It is read as UTF-8 (Latin-1
  as a fallback, a byte-order mark is dropped) and trimmed. New tests write
  the question, trimmed, followed by one newline.
- **The `.bib` file** is BibTeX. See §3.2 for how references are counted.
- **The screenshots, PDF and HTML** are not opened; only their presence and
  size are checked.

### 2.5 Ground truth and annotations (optional)

Two kinds of file hold what the tester enters in the app. Both are optional:
a test is complete without them, and they never add an error.

- **Ground truth** — `ID/ID_ground_truth.bib`, one per test (also for a
  multi-RQ test): the BibTeX entry of a published paper that asks the same
  research questions. It should hold exactly one entry; with none or several,
  the test gets a warning and the first entry is used. The app shows it as an
  APA 7 reference (§5) and copies it, or just its DOI.
- **Annotation** — the tester's brief note on a research question:
  `ID_annotation.md` in `ID_query/`, or `ID_variantN_annotation.md` in
  `ID_query_variantN/` (or in whichever folder holds that variant's query
  files, if it has an older name). Plain text, saved trimmed with one trailing
  newline; clearing the note deletes the file.

## 3. Checks

### 3.1 Errors

An error means the test is incomplete or wrong:

- an artifact is missing (the message gives the expected path);
- there is more than one file for the same artifact;
- the BibTeX file's name has no count (`ABCD-123_references.bib`) or the
  count isn't a number;
- **the count in the BibTeX file's name doesn't match the entries in the file**;
- the research question file is empty;
- a file or folder can't be read.

### 3.2 Counting references

The count is the number of BibTeX entries: every `@type{key, …}` or
`@type(key, …)` at the top level of the file, of any type except `@string`,
`@preamble` and `@comment`. The body of each entry is skipped by matching
braces, so an `@` inside a field value (an e-mail address, `\url{…}`, a title)
is never counted, and neither is anything inside `@comment{…}`. Text between
entries is a comment in BibTeX and is ignored. Type names are matched without
regard to case, and spaces are allowed between `@` and the type.

Citation keys may contain spaces (`@article{Smith 2020, …}`). BibTeX itself
doesn't allow them, but the tool under test sometimes writes them, so they are
tolerated when verifying a file: such an entry counts like any other, and no
warning is given. Spaces before and after a key are ignored, so `{ Smith 2020 ,`
and `{Smith 2020,` are the same key when looking for clashes (§3.4). A tab or line
break still ends a key. This applies only to checking; the app never rewrites
a BibTeX file.

### 3.3 Warnings

A warning is worth a look but doesn't make the test incomplete:

- an older name (§2.3);
- variant numbering with a gap (variants 1, 2 and 4), a variant 0, or only one
  variant in a multi-RQ test;
- single-RQ items in a test that has variants;
- an unrecognised item in a test folder or query folder (a name that doesn't
  start with `ID_`, or doesn't match any artifact), a query-folder file left at
  the top of the test folder, or a file named for another variant;
- an empty (0-byte) screenshot, BibTeX file, PDF or HTML file;
- in the BibTeX file: entries without a key, or a file that ends inside an
  entry (unbalanced braces).

A test's **status** is Errors if it has any error, else Warnings if it has any
warning, else Complete. A research question's row status counts its own
issues and the test-level ones.

### 3.4 Clashing citation keys (reported, not a problem)

The tool under test sometimes gives separate references the same citation
key. These **key clashes** are listed for information only: they are neither
errors nor warnings, every clashing entry still counts as a reference, and
they don't affect the status. Keys are compared without regard to case, as
biber does, and each entry is identified by its key as written and the line
its `@` is on, for example:

```
Smith2025 (line 94) and Smith2025 (line 255)
```

The app shows them in the detail pane (a "clashing citation keys" row under
the reference count) and as a count in the Research Questions table; both
exports list them too (§4).

### 3.5 Export dates (the date of a test)

A BibTeX file may say when it was exported, as Scopus does at the top of its
exports:

```
Scopus
EXPORT DATE: 02 October 2026
```

Any `EXPORT DATE` (in any case, with or without the colon) anywhere in the
file counts, including inside a field. The date may be written `02 October
2026`, `2 Oct 2026`, `October 2, 2026`, `2026-10-02` or `02/10/2026` (day
first); anything after the date on the line is ignored. A test's **date** is
the export date of its BibTeX files; when its variants were exported on
different days (or one file gives several dates) it is the range, written
`1–2 October 2026`, `30 September – 2 October 2026` or
`31 December 2025 – 2 January 2026`. A file without an export date is not a
problem; the test just has no date (or a range over the files that have one).

## 4. Exports

Both exports cover every test in the workspace, whatever the sidebar filter
or search shows.

### 4.1 CSV

UTF-8 with a byte-order mark (so Excel and Numbers detect the encoding),
CRLF line endings, RFC 4180 quoting (fields with commas, quotes or line
breaks are quoted; quotes are doubled). One header row, then one row per
research question:

| Column | Contents |
| --- | --- |
| Test ID | the folder name |
| Type | `Single RQ` or `Multiple RQs` |
| Variant | the variant number; empty for single-RQ |
| Research Question | the text of `RQ_asked.md`; empty if missing |
| References Found | entries counted in the BibTeX file; empty if none |
| References in File Name | the `n<count>` in its name; empty if none |
| Count Matches | `Yes`, `No`, or empty when either count is unknown |
| Status | `Complete`, `Warnings` or `Errors` (the row status) |
| Issues | `Error: …` and `Warning: …` messages, separated by `; `, test-level first |
| Citation Key Clashes | one entry per clashing key, as in §3.4, separated by `; `; empty if none |
| Annotation | the research question's annotation (§2.5); empty if none |
| Ground Truth (APA 7) | the test's ground truth as a plain-text APA 7 reference, repeated on each of its rows |
| Ground Truth DOI | its DOI as `doi:10.1234/abcd9999`; empty if none |
| Export Date | the research question's export date (§3.5) as `2026-10-02`, or `2026-10-01 to 2026-10-02`; empty if none |

### 4.2 HTML

A single page with its styles inline and no scripts, fonts, images or other
external resources, so it can be e-mailed, archived or printed as it is. It
shows the workspace name and export time, a summary bar and sentence (tests
complete, with warnings and with errors; research questions; references), and
a table with one group per test: type, variant, research question, references
found, the count in the file name (marked ≠ when it differs), status, and the
test's issues underneath, followed by its key clashes (marked "Key clash", in
a neutral colour). Annotations appear under their research questions, the
ground truth (with its italics) above the test's issues, and the test's date
(§3.5) under its ID.

### 4.3 Markdown

GitHub-flavoured Markdown, laid out for reading on GitHub, GitLab or a similar
Git host (and readable as plain text):

- a `#` title, the workspace name and export time, and a one-line summary;
- an overview table (test, type, number of research questions, references per
  research question, export date with a short month, as in `23 Sep 2026` or
  `30 Sep – 2 Oct 2026`, ground truth as "Smith et al. (2024)", status),
  whose test IDs link to the sections below;
- a `##` section per test (its anchor is the ID in lowercase, `#abcd-123`):
  status, type, references and date; a link to the test folder; the ground
  truth with its italics and a link to its BibTeX file; a table of research
  questions (variant, question, references found, annotation, or
  `_(No annotation found.)_`); links to the screenshots, the references BIB
  and the reports (per variant for a multi-RQ test; the research question
  and annotation files aren't linked, since their text is in the table); then
  lists of issues and key clashes, when there are any. A reference count that
  doesn't match the file name appears under Issues.

The export is meant to be saved at the top of the workspace as **README.md**
(the Save panel suggests exactly that), so a Git host shows it on the
workspace's front page. The links are relative to wherever it is saved, with
`../` if that is outside the workspace, and percent-encoded, so they work on
GitHub, GitLab and in a local clone.

Status is shown as ✅ Complete, ⚠️ Warnings or ❌ Errors, so it reads without
colour. Text from the workspace is escaped (`|`, `*`, `_`, `<`, backticks and
the like), so a research question can never break a table or turn into
formatting or HTML; line breaks in table cells become `<br>`. It follows the system's light or dark appearance and
has a print layout.

## 5. APA 7 references

The ground truth is formatted in APA 7th edition style, as in QDVC Bibliotheca:
a pragmatic formatter for the common entry types, not a full CSL engine.

| Entry type | Layout |
| --- | --- |
| `article` | Authors (Year). Title. *Journal*, *Volume*(Issue), pages. DOI |
| `inproceedings`, `incollection`, `inbook` | Authors (Year). Title. In E. Editor (Ed.), *Book title* (pp. pages). Publisher. DOI |
| `book`, `proceedings` | Authors (Year). *Title* (edition ed.). Publisher. DOI |
| `phdthesis`, `mastersthesis` | Author (Year). *Title* [Doctoral dissertation, School]. DOI |
| `techreport` | Authors (Year). *Title* (Report No. N). Institution. DOI |
| anything else | Authors (Year). *Title*. Publisher or howpublished. DOI |

- **The DOI is written `doi:10.1234/abcd9999`**, not as a URL; `https://doi.org/`,
  `http://dx.doi.org/` and `doi:` prefixes in the `doi` field are removed
  first. With no DOI, the `url` field (or a URL in `howpublished`) is used.
- **Authors**: "Surname, F. M." with initials for every given name
  (hyphenated names keep the hyphen, "J.-P."), particles kept with the surname
  ("van der Berg, J."), a name wholly in braces kept as an organisation, up to
  20 authors joined with ", &"; with 21 or more, the first 19, ". . ." and the
  last. A book with only editors lists them with "(Ed.)" or "(Eds.)"; with no
  author at all, the title moves to the front.
- **Year**: `year`, or the first four digits of `date`, or "n.d.".
- **Text**: LaTeX accents and escapes become characters (`{\"u}` → ü, `\&` → &),
  braces are removed, `--` becomes an en dash. Titles are used as written (no
  automatic sentence case, which would lower-case proper nouns).
- Parsing understands brace- and quote-delimited values, `#` concatenation,
  `@string` macros and the month macros.

Copying the reference puts rich text (RTF and HTML, so italics survive a paste
into Word, Pages or Mail) and plain text on the pasteboard; copying the DOI
puts just the DOI, without the `doi:` prefix (`10.1234/abcd9999`).

## 6. New tests

New Test creates `ID/` with the standard names of §2.1 or §2.2. The dropped
files are **copied**, never moved or changed; the research question files are
written from the text typed. The BibTeX file's entries are counted again when
the test is created, and that count goes in its name. An annotation typed
for a research question is written as its `…_annotation.md` (§2.5); left
empty, no file is written. The folder is assembled
under a hidden name (`.ID.creating-<uuid>`) and renamed into place at the end,
so a failure part-way leaves nothing behind. A test ID that already exists in
the workspace is refused.

### 6.1 Adding variants to an existing test

Test → Add Variants… adds research questions to an existing **multi-RQ**
test. The new variants are numbered on from the test's highest variant (a
test with variants 1–3 gains 4, 5 and so on; gaps are not filled), and each
gets the same files as in §2.2, copied in under the standard names, plus its
annotation if one is typed. Nothing already in the test is changed: if any of
the new names is already taken, nothing is written. The files are assembled
in a hidden folder inside the test (`.adding-variants-<uuid>`) and moved into
place at the end. A single-RQ test can't take variants this way, because its
files would have to be renamed to `…_variant1_…`.
