#!/usr/bin/env python3
"""Regenerate sample-workspace/: a small workspace of test runs that shows
every kind of result the app reports.

    DEMO-101  single RQ, complete
    DEMO-102  three variants, complete
    DEMO-103  single RQ, errors: the file name says 20 references but the
              BibTeX has 18, and the report DOM is missing
    DEMO-104  two variants, warnings: variant 2 uses the older names
              (DEMO-104_variant2/ and DEMO-104_query_variant2_references_n6.bib)
    DEMO-105  variants 1, 2 and 4, errors: a gap in the numbering (warning)
              and variant 4 has no response screenshot (error)
    DEMO-110  single RQ, complete, with no references found (n0)

Every BibTeX entry has an abstract except in DEMO-105 variant 2, where only
2 of 7 do (more than half missing is a warning).

workspace.yml turns on both DOM checks. Every report DOM shows its research
question and "Show all N references", except DEMO-104 variant 1, whose DOM
shows a reworded question (a warning).

Every BibTeX file starts with a Scopus-style "EXPORT DATE:" line, so each
test has a date; DEMO-102's variants were exported on three different days,
so its date is a range.

DEMO-101 and DEMO-102 also have a ground truth (DEMO-1xx_ground_truth.bib),
and two of DEMO-102's research questions have annotations; both are
optional and don't change a test's status.

plus README.txt, which is not a test and is listed as another item.

The screenshots are small solid-colour PNGs and the reports are one-page PDFs
and HTML files: just enough to open. No dependencies beyond Python 3.

Usage:

    python3 tools/make_sample_workspace.py   # rewrites sample-workspace/

Tests/AutoLitReviewCoreTests/SampleWorkspaceTests.swift checks the app's
reading of this workspace, so update it when you change the cases here.
"""

import html as htmllib
import shutil
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT / "sample-workspace"

AUTHORS = ["Nguyen", "Okafor", "Lindqvist", "Haddad", "Moreau", "Tanaka", "Silva", "Kowalski",
           "Mensah", "Ivanova", "Romero", "Fischer", "Achterberg", "Barros", "Chen", "Dlamini",
           "Eriksen", "Farouk", "Gupta", "Hollis"]
VENUES = ["Information Systems Journal", "MIS Quarterly", "Journal of the AIS",
          "European Journal of Information Systems", "Proceedings of ICIS",
          "Proceedings of ACIS", "Journal of Systems and Software"]


# --------------------------------------------------------------------------
# File contents


def png(width=96, height=60, rgb=(120, 140, 170)):
    """A solid-colour RGB PNG with a lighter band, as a stand-in screenshot."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    light = tuple(min(255, c + 70) for c in rgb)
    rows = b""
    for y in range(height):
        colour = light if 6 <= y < 14 else rgb
        rows += b"\x00" + bytes(colour) * width
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def pdf(title):
    """A one-page PDF with one line of text."""
    text = title.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    stream = f"BT /F1 18 Tf 72 720 Td ({text}) Tj ET".encode("latin-1")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        b"/Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return out


def html(title, question, refs):
    """A stand-in report DOM: the question as asked (split across a line, and
    with an inline tag, as real pages do) and a "Show all N references" button."""
    words = htmllib.escape(question, quote=False).split(" ")
    middle = len(words) // 2
    shown = " ".join(words[:middle]) + "\n      <span class=\"rq-rest\">" + " ".join(words[middle:]) + "</span>"
    button = f"Show all {refs} references" if refs != 1 else "Show all 1 reference"
    return (f"<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>{title}</title>\n"
            f"<script>window.__STATE__ = {{\"note\": \"not page text\"}};</script></head>\n"
            f"<body>\n  <h1>{title}</h1>\n  <p class=\"rq\">{shown}</p>\n"
            f"  <p>Generated literature review (sample).</p>\n"
            f"  <button type=\"button\">{button}</button>\n</body></html>\n")


def bibtex(count, seed, exported="02 October 2026", abstracts=None):
    """`count` entries; the first `abstracts` of them (all by default) have an abstract."""
    with_abstract = count if abstracts is None else abstracts
    header = f"Scopus\nEXPORT DATE: {exported}\n\n"
    if count == 0:
        return header + "% The tool returned no references for this research question.\n"
    entries = []
    for i in range(count):
        author = AUTHORS[(seed + i) % len(AUTHORS)]
        year = 2015 + (seed * 3 + i) % 11
        venue = VENUES[(seed + i * 2) % len(VENUES)]
        entries.append(
            f"@article{{{author.lower()}{year}s{seed}r{i + 1},\n"
            f"  author = {{{author}, A. and Smith, J.}},\n"
            f"  title = {{Sample study {i + 1} for seed {seed}}},\n"
            f"  journal = {{{venue}}},\n"
            f"  year = {{{year}}},\n"
            + (f"  abstract = {{This sample study {i + 1} reports findings for seed {seed}.}},\n"
               if i < with_abstract else "")
            + "}\n")
    return header + "\n".join(entries)


# --------------------------------------------------------------------------
# Writers


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))


def single(test_id, question, refs, named=None, skip=(), dom_question=None):
    folder = WORKSPACE / test_id
    query = folder / f"{test_id}_query"
    files = {
        "query": (query / f"{test_id}_query_asked.png", png(rgb=(110, 140, 175))),
        "response": (query / f"{test_id}_response_received.png", png(rgb=(120, 165, 140))),
        "rq": (query / f"{test_id}_RQ_asked.md", question + "\n"),
        "bib": (folder / f"{test_id}_references_n{refs if named is None else named}.bib",
                bibtex(refs, sum(map(ord, test_id)) % 97)),
        "pdf": (folder / f"{test_id}_report.pdf", pdf(f"{test_id} literature review")),
        "dom": (folder / f"{test_id}_report_DOM.html",
                html(f"{test_id} literature review", dom_question or question, refs)),
    }
    for key, (path, data) in files.items():
        if key not in skip:
            write(path, data)


def variant(test_id, number, question, refs, old_names=False, skip=(), exported="02 October 2026",
            dom_question=None, abstracts=None):
    folder = WORKSPACE / test_id
    query_name = f"{test_id}_variant{number}" if old_names else f"{test_id}_query_variant{number}"
    query = folder / query_name
    prefix = f"{test_id}_variant{number}_"
    top_prefix = f"{test_id}_query_variant{number}_" if old_names else prefix
    title = f"{test_id} variant {number} literature review"
    files = {
        "query": (query / f"{prefix}query_asked.png", png(rgb=(110, 140, 175))),
        "response": (query / f"{prefix}response_received.png", png(rgb=(120, 165, 140))),
        "rq": (query / f"{prefix}RQ_asked.md", question + "\n"),
        "bib": (folder / f"{top_prefix}references_n{refs}.bib", bibtex(refs, number * 7 + len(test_id), exported, abstracts)),
        "pdf": (folder / f"{prefix}report.pdf", pdf(title)),
        "dom": (folder / f"{prefix}report_DOM.html", html(title, dom_question or question, refs)),
    }
    for key, (path, data) in files.items():
        if key not in skip:
            write(path, data)


def main():
    if WORKSPACE.exists():
        shutil.rmtree(WORKSPACE)
    WORKSPACE.mkdir()

    single("DEMO-101", "What are the reported effects of remote work on software developer productivity?", 12)

    variant("DEMO-102", 1, "How do organisations govern the use of generative AI in knowledge work?", 8,
            exported="30 September 2026")
    variant("DEMO-102", 2, "What governance mechanisms do organisations use for generative AI tools?", 5,
            exported="01 October 2026")
    variant("DEMO-102", 3, "Which policies, roles and controls guide employee use of generative AI?", 11)

    write(WORKSPACE / "DEMO-101" / "DEMO-101_ground_truth.bib", """@article{okafor2023remote,
  author = {Okafor, Chidi and Lindqvist, Anna-Karin and Moreau, Lu{\\'c}},
  title = {Remote work and developer productivity: {A} systematic literature review},
  journal = {Journal of Systems and Software},
  volume = {198},
  pages = {111602},
  year = {2023},
  doi = {https://doi.org/10.1016/j.jss.2023.111602}
}
""")
    write(WORKSPACE / "DEMO-102" / "DEMO-102_ground_truth.bib", """@inproceedings{haddad2024genai,
  author = {Haddad, Rania and Silva, Pedro},
  title = {Governing generative {AI} at work: {A} review of organisational policies},
  booktitle = {Proceedings of the 45th International Conference on Information Systems},
  pages = {1--17},
  year = {2024},
  publisher = {Association for Information Systems},
  doi = {10.5555/icis2024.1234}
}
""")
    write(WORKSPACE / "DEMO-102" / "DEMO-102_query_variant1" / "DEMO-102_variant1_annotation.md",
          "Broadest wording. Found the ground truth paper.\n")
    write(WORKSPACE / "DEMO-102" / "DEMO-102_query_variant2" / "DEMO-102_variant2_annotation.md",
          "Narrower; missed two policy studies the ground truth cites.\n")

    single("DEMO-103", "What barriers do small businesses face when adopting cloud accounting software?",
           18, named=20, skip=("dom",))

    # The DOM shows a reworded question, so the RQ text check warns.
    variant("DEMO-104", 1, "How is digital twin technology used in hospital operations management?", 4,
            dom_question="How are digital twins used in hospital operations management?")
    variant("DEMO-104", 2, "What are the applications of digital twins in healthcare operations?", 6, old_names=True)

    variant("DEMO-105", 1, "What factors influence citizens\u2019 trust in e-government services?", 9)
    # Only 2 of 7 entries have an abstract (a warning).
    variant("DEMO-105", 2, "Which antecedents of trust in digital public services have been studied?", 7,
            abstracts=2)
    variant("DEMO-105", 4, "How has trust in e-government been measured?", 3, skip=("response",))

    single("DEMO-110", "What is known about the use of blockchain for academic credential verification in Oceania?", 0)

    write(WORKSPACE / "workspace.yml",
          "# Settings for QDVC Auto Lit Review Tester (docs/FILE_FORMAT.md \u00a71.1)\n"
          "dom_checks:\n"
          "  rq_text_string_check: True     # each RQ's exact text must appear in its report DOM\n"
          "  all_n_references_check: True   # the DOM must say \"Show all N references\"\n")
    write(WORKSPACE / "README.txt",
          "Sample workspace for QDVC Auto Lit Review Tester.\n"
          "Regenerate it with tools/make_sample_workspace.py.\n")
    print(f"Wrote {WORKSPACE.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
