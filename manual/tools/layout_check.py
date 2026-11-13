"""Automated layout checks for the printed manual (complements the visual review).

  manual/.venv/Scripts/python.exe manual/tools/layout_check.py manual/dist/DevOps-Delivery-Observability-Handbook.pdf \
      [--accept-gaps 12,183,192,198 | --accept-gaps-file manual/layout-accepted-gaps.txt]

For every page it measures where the content really is (text, images and vector
objects, ignoring the footer) and reports:
  * gaps   - pages whose content stops early (less than --min-fill of the text area is
             used) although the next page does not start a new chapter
  * overflow - characters that extend past the right margin
  * blank  - pages with almost no content

Exit code 1 if any page overflows, any page is blank, or a gap appears on a page that is
not listed in --accept-gaps (gaps reviewed by a person and kept on purpose, e.g. a section
heading moved to the next page together with its large figure). Up to v1.0 this tool only
printed its findings and always exited 0.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pypdfium2 as pdfium
import pypdfium2.raw as pdfium_raw
from pypdf import PdfReader

MM = 72 / 25.4


def chapter_start_pages(path: str) -> set[int]:
    reader = PdfReader(path)
    starts = set()
    for item in reader.outline:
        if not isinstance(item, list):
            starts.add(reader.get_destination_page_number(item) + 1)
    return starts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("--min-fill", type=float, default=0.6)
    ap.add_argument("--accept-gaps", default="", help="comma-separated page numbers whose gap was reviewed and accepted")
    ap.add_argument("--accept-gaps-file", help="file with the accepted pages (comma-separated; # starts a comment)")
    a = ap.parse_args()
    spec = a.accept_gaps
    if a.accept_gaps_file:
        lines = Path(a.accept_gaps_file).read_text(encoding="utf-8").splitlines()
        spec += "," + ",".join(line.split("#", 1)[0] for line in lines)
    accepted = {int(p) for p in spec.split(",") if p.strip()}

    starts = chapter_start_pages(a.pdf)
    doc = pdfium.PdfDocument(a.pdf)
    gaps, overflow, blank = [], [], []
    for i in range(len(doc)):
        page = doc[i]
        w, h = page.get_size()
        bottom_limit, top_limit = 17 * MM, h - 17 * MM     # footer and header bands
        right_limit = w - 16 * MM + 1.5 * MM                 # right margin + tolerance
        tops, bottoms = [], []
        # Content = text characters + raster images (screenshots). Chrome emits tens of
        # thousands of small vector paths per page; text inside tables, code blocks and
        # Mermaid diagrams is enough to locate those elements.
        for obj in page.get_objects(max_depth=1):
            if obj.type != pdfium_raw.FPDF_PAGEOBJ_IMAGE:
                continue
            l, b, r, t = obj.get_bounds()
            if t > bottom_limit and b < top_limit:
                tops.append(t)
                bottoms.append(b)
        tp = page.get_textpage()
        far = 0
        for c in range(tp.count_chars()):
            l, b, r, t = tp.get_charbox(c)
            if b <= bottom_limit or t >= top_limit or (r - l) <= 0:
                continue
            tops.append(t)
            bottoms.append(b)
            if r > right_limit and not tp.get_text_range(c, 1).isspace():
                far += 1
        if far:
            overflow.append((i + 1, far))
        if not tops:
            blank.append(i + 1)
            continue
        used = (min(max(tops), top_limit) - max(min(bottoms), bottom_limit)) / (top_limit - bottom_limit)
        if used < a.min_fill and (i + 2) not in starts and i + 1 != len(doc):
            gaps.append((i + 1, round(used, 2)))
    print(f"pages: {len(doc)}  chapter starts: {sorted(starts)}")
    print(f"gaps (< {a.min_fill:.0%} of the text area used, next page is not a chapter start): {len(gaps)}")
    for p, u in gaps:
        print(f"  page {p}: {u:.0%} used")
    print(f"overflow past the right margin: {len(overflow)} page(s) {overflow[:20]}")
    print(f"blank pages: {blank}")
    unaccepted = [p for p, _ in gaps if p not in accepted]
    stale = sorted(accepted - {p for p, _ in gaps})
    if stale:
        print(f"note: accepted gap pages that are no longer gaps (update --accept-gaps): {stale}")
    problems = []
    if overflow:
        problems.append(f"{len(overflow)} page(s) overflow")
    if blank:
        problems.append(f"{len(blank)} blank page(s)")
    if unaccepted:
        problems.append(f"unreviewed gaps on pages {unaccepted}")
    print(f"RESULT: {'FAIL - ' + '; '.join(problems) if problems else 'PASS'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
