"""Legibility check for the figures of the Publication Edition.

The built HTML is laid out at the printed column width (Edge, print media), and for every figure the size of its
smallest text ON PAPER is computed:

  Mermaid diagram   computed font size of every label in the rendered SVG x the scale at which the SVG is placed
  chart (SVG image) smallest font-size in the SVG source x the scale at which the image is placed
  screenshot / terminal record   reported with its scale only: its text is whatever the tool drew

A figure whose smallest text is below --min-pt fails. This is the automatic counterpart of the page-by-page review:
it catches diagrams that the layout scaled down until nobody can read them.

  manual/.venv/Scripts/python.exe v2/manual/pub/build_pub.py --html-only
  manual/.venv/Scripts/python.exe v2/manual/pub/figcheck.py [--min-pt 6.5] [--json report.json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[3]
HTML = ROOT / "manual" / "build" / "manual.html"
COLUMN_PX = 673          # A4 minus the 16 mm side margins = 178 mm = 672.8 CSS px

COLLECT = """
() => {
  const out = [];
  let chapter = 0, n = 0;
  for (const el of document.querySelectorAll('main h1, main figure')) {
    if (el.tagName === 'H1') {
      if (el.classList.contains('unnumbered')) { chapter = 0; } else { chapter = Number((el.querySelector('.header-section-number') || {}).textContent || 0); n = 0; }
      continue;
    }
    n += 1;
    const cap = el.querySelector('figcaption');
    const rec = {chapter, n, caption: cap ? cap.textContent.trim().slice(0, 70) : '', cls: el.className};
    const svg = el.querySelector('pre.mermaid svg');
    const img = el.querySelector('img');
    if (svg) {
      const vb = svg.viewBox.baseVal, r = svg.getBoundingClientRect();
      rec.type = 'mermaid'; rec.nat = [vb.width, vb.height]; rec.box = [r.width, r.height]; rec.scale = r.width / vb.width;
      let min = Infinity, text = '';
      svg.querySelectorAll('text, tspan, foreignObject span, foreignObject p, foreignObject div').forEach((t) => {
        const s = (t.textContent || '').trim();
        if (!s) return;
        const fs = parseFloat(getComputedStyle(t).fontSize);
        if (fs < min) { min = fs; text = s.slice(0, 30); }
      });
      rec.font = min === Infinity ? null : min; rec.sample = text;
    } else if (img) {
      const r = img.getBoundingClientRect();
      rec.type = 'img'; rec.src = img.getAttribute('src'); rec.cls = (rec.cls + ' ' + img.className).trim();
      rec.nat = [img.naturalWidth, img.naturalHeight]; rec.box = [r.width, r.height]; rec.scale = r.width / img.naturalWidth;
    }
    out.push(rec);
  }
  return out;
}
"""


def svg_min_font(path: Path) -> float | None:
    sizes = [float(x) for x in re.findall(r'font-size="([0-9.]+)"', path.read_text(encoding="utf-8"))]
    return min(sizes) if sizes else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-pt", type=float, default=6.5, help="smallest acceptable text size on paper, in points")
    ap.add_argument("--json", default=None)
    ap.add_argument("--quiet", action="store_true", help="print only the figures that fail and the result line")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    if not HTML.exists():
        print(f"{HTML} not found: run build_pub.py --html-only first", file=sys.stderr)
        return 1
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge")
        page = browser.new_page(viewport={"width": COLUMN_PX, "height": 1000})
        page.emulate_media(media="print")
        page.goto(HTML.as_uri())
        page.wait_for_function("document.body.dataset.ready === '1'", timeout=300_000)
        figures = page.evaluate(COLLECT)
        browser.close()

    failed = 0
    rows = []
    for f in figures:
        kind = "concept"
        cls = f.get("cls", "")
        for k in ("data", "shot", "term", "model"):
            if re.search(rf"(^|\s){k}(\s|$)", cls):
                kind = k
        font = f.get("font")
        if f["type"] == "img" and f["src"].endswith(".svg"):
            font = svg_min_font((HTML.parent / f["src"]).resolve())
        pt = round(font * f["scale"] * 0.75, 2) if font else None
        f.update(kind=kind, font=font, pt=pt)
        checked = pt is not None
        ok = (pt >= args.min_pt) if checked else True
        failed += not ok
        label = f"{f['chapter']}-{f['n']}" if f["chapter"] else f"front/back {f['n']}"
        rows.append((ok, label, f))
    for ok, label, f in rows:
        if args.quiet and ok:
            continue
        size = f"{f['pt']:.1f} pt" if f["pt"] is not None else "   -   "
        print(f"{'ok  ' if ok else 'FAIL'} {label:<13} {f['type']:<7} {f['kind']:<7} scale {f['scale']:.2f}  "
              f"{f['nat'][0]:.0f}x{f['nat'][1]:.0f} -> {f['box'][0]:.0f}x{f['box'][1]:.0f}  text {size}  {f['caption'][:34]}")
    measured = [f["pt"] for _, _, f in rows if f["pt"] is not None]
    if args.json:
        Path(args.json).write_text(json.dumps([f for _, _, f in rows], ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"RESULT: {'PASS' if not failed else 'FAIL'} - {len(rows)} figure(s), {len(measured)} with measurable text, "
          f"smallest {min(measured):.1f} pt, {failed} below {args.min_pt} pt")
    return 0 if not failed else 2


if __name__ == "__main__":
    sys.exit(main())
