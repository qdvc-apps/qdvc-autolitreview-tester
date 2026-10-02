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
- in the BibTeX file: duplicate citation keys (compared without regard to
  case, as biber does), entries without a key, or a file that ends inside an
  entry (unbalanced braces).

A test's **status** is Errors if it has any error, else Warnings if it has any
warning, else Complete. A research question's row status counts its own
issues and the test-level ones.

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

### 4.2 HTML

A single page with its styles inline and no scripts, fonts, images or other
external resources, so it can be e-mailed, archived or printed as it is. It
shows the workspace name and export time, a summary bar and sentence (tests
complete, with warnings and with errors; research questions; references), and
a table with one group per test: type, variant, research question, references
found, the count in the file name (marked ≠ when it differs), status, and the
test's issues underneath. It follows the system's light or dark appearance and
has a print layout.

## 5. New tests

New Test creates `ID/` with the standard names of §2.1 or §2.2. The dropped
files are **copied**, never moved or changed; the research question files are
written from the text typed. The BibTeX file's entries are counted again when
the test is created, and that count goes in its name. The folder is assembled
under a hidden name (`.ID.creating-<uuid>`) and renamed into place at the end,
so a failure part-way leaves nothing behind. A test ID that already exists in
the workspace is refused.
