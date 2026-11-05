"""Rasterize PDF pages to PNG for visual review: pdf2png.py IN.pdf OUTDIR [--pages 1,3-5] [--scale 1.2]"""
import argparse
from pathlib import Path

import pypdfium2 as pdfium

ap = argparse.ArgumentParser()
ap.add_argument("pdf")
ap.add_argument("outdir")
ap.add_argument("--pages", default="")
ap.add_argument("--scale", type=float, default=1.2)
a = ap.parse_args()
doc = pdfium.PdfDocument(a.pdf)
wanted = set()
for part in filter(None, a.pages.split(",")):
    lo, _, hi = part.partition("-")
    wanted.update(range(int(lo), int(hi or lo) + 1))
out = Path(a.outdir)
out.mkdir(parents=True, exist_ok=True)
for i in range(len(doc)):
    if wanted and (i + 1) not in wanted:
        continue
    doc[i].render(scale=a.scale).to_pil().save(out / f"page-{i + 1:03d}.png")
print(f"{len(doc)} pages; rendered {len(wanted) or len(doc)} -> {out}")
