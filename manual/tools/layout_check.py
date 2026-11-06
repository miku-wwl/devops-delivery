"""Automated layout checks for the printed manual (complements the visual review).

  manual/.venv/Scripts/python.exe manual/tools/layout_check.py manual/dist/DevOps-Delivery-Observability-Handbook.pdf

For every page it measures where the content really is (text, images and vector
objects, ignoring the footer) and reports:
  * gaps   - pages whose content stops early (less than --min-fill of the text area is
             used) although the next page does not start a new chapter
  * overflow - characters that extend past the right margin
  * blank  - pages with almost no content
"""
from __future__ import annotations

import argparse
import sys

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
    a = ap.parse_args()

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
    return 0


if __name__ == "__main__":
    sys.exit(main())
