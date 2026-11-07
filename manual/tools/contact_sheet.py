"""Tile PDF pages into contact sheets for page-by-page visual QA.

  manual/.venv/Scripts/python.exe manual/tools/contact_sheet.py IN.pdf OUTDIR [--per-sheet 4] [--cols 2]
      [--page-height 900] [--pages 1-40]

Every sheet shows the page numbers in the top-left corner of each tile, so a problem
seen on a sheet can be traced back to its page and inspected at full size with pdf2png.py.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import pypdfium2 as pdfium
from PIL import Image, ImageDraw, ImageFont


def parse_pages(spec: str, total: int) -> list[int]:
    if not spec:
        return list(range(1, total + 1))
    pages: list[int] = []
    for part in spec.split(","):
        lo, _, hi = part.partition("-")
        pages.extend(range(int(lo), int(hi or lo) + 1))
    return [p for p in pages if 1 <= p <= total]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("outdir")
    ap.add_argument("--per-sheet", type=int, default=4)
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("--page-height", type=int, default=900, help="height of one tile in pixels")
    ap.add_argument("--pages", default="")
    a = ap.parse_args()

    doc = pdfium.PdfDocument(a.pdf)
    pages = parse_pages(a.pages, len(doc))
    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    try:
        font = ImageFont.truetype("arialbd.ttf", 26)
    except OSError:
        font = ImageFont.load_default()

    for start in range(0, len(pages), a.per_sheet):
        chunk = pages[start:start + a.per_sheet]
        tiles = []
        for p in chunk:
            page = doc[p - 1]
            scale = a.page_height / page.get_height()
            img = page.render(scale=scale).to_pil().convert("RGB")
            ImageDraw.Draw(img).rectangle([0, 0, img.width - 1, img.height - 1], outline=(150, 150, 150), width=2)
            tiles.append((p, img))
        cols = min(a.cols, len(tiles))
        rows = (len(tiles) + cols - 1) // cols
        tw = max(t.width for _, t in tiles)
        th = max(t.height for _, t in tiles)
        gap = 12
        sheet = Image.new("RGB", (cols * tw + (cols + 1) * gap, rows * th + (rows + 1) * gap), (60, 60, 60))
        draw = ImageDraw.Draw(sheet)
        for i, (p, img) in enumerate(tiles):
            x = gap + (i % cols) * (tw + gap)
            y = gap + (i // cols) * (th + gap)
            sheet.paste(img, (x, y))
            draw.rectangle([x, y, x + 76, y + 36], fill=(200, 30, 30))
            draw.text((x + 8, y + 4), f"p{p}", fill=(255, 255, 255), font=font)
        name = out / f"sheet-{chunk[0]:03d}-{chunk[-1]:03d}.png"
        sheet.save(name)
    print(f"{len(pages)} pages -> {(len(pages) + a.per_sheet - 1) // a.per_sheet} sheets in {out}")


if __name__ == "__main__":
    main()
