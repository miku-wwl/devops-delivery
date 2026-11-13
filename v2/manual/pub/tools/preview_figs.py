"""Review sheet for generated figures: lays the named SVGs out at their printed width (640 px) and takes one
screenshot, so several diagrams can be checked at a readable size in one image.

  manual/.venv/Scripts/python.exe v2/manual/pub/tools/preview_figs.py --out sheet.png concept-saga concept-outbox ...
  manual/.venv/Scripts/python.exe v2/manual/pub/tools/preview_figs.py --out sheet.png --match "concept-*"
"""
from __future__ import annotations

import argparse
import fnmatch
from pathlib import Path

from playwright.sync_api import sync_playwright

FIG = Path(__file__).resolve().parents[2] / "figures"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--match", default=None)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("--scale", type=float, default=1.5)
    args = ap.parse_args()
    names = list(args.names)
    if args.match:
        names += sorted(p.stem for p in FIG.glob("*.svg") if fnmatch.fnmatch(p.stem, args.match))
    cells = "".join(
        f'<div class="c"><div class="n">{n}</div><img src="{(FIG / (n + ".svg")).as_uri()}" width="640"></div>' for n in names)
    html = ("<!DOCTYPE html><meta charset='utf-8'><style>body{margin:8px;background:#667;font-family:Segoe UI}"
            f".g{{display:grid;grid-template-columns:repeat({args.cols},640px);gap:10px;align-items:start}}"
            ".c{background:#fff;border:1px solid #334}.n{font-size:11px;background:#223;color:#fff;padding:1px 6px}"
            "img{display:block}</style><div class='g'>" + cells + "</div>")
    page_file = Path(args.out).with_suffix(".html")
    page_file.write_text(html, encoding="utf-8")
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge")
        page = browser.new_page(viewport={"width": 16 + args.cols * 650, "height": 600}, device_scale_factor=args.scale)
        page.goto(page_file.as_uri())
        page.wait_for_load_state("networkidle")
        page.screenshot(path=args.out, full_page=True)
        browser.close()
    page_file.unlink()
    print(f"{len(names)} figure(s) -> {args.out}")


if __name__ == "__main__":
    main()
