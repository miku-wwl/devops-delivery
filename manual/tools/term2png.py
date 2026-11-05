"""Render a recorded transcript (automation/evidence/transcript.sh) as a terminal-style PNG.

The PNG is a faithful rendering of the captured text - nothing is edited. Long
outputs can be cut with --lines or --max-lines; any cut is marked explicitly in
the image ("... N lines omitted ..."). The title bar shows when the transcript
was recorded, so the image never pretends to be a live screen grab.

  manual/.venv/Scripts/python.exe manual/tools/term2png.py evidence/p0/verify.log evidence/p0/verify.png \
      --title "devops-lab · 环境验证" --lines 4-40 --max-lines 60
"""
from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

from playwright.sync_api import sync_playwright

ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")

CSS = """
body { margin:0; background:#ffffff; }
.term { display:inline-block; min-width:var(--w); max-width:var(--w); border-radius:8px; overflow:hidden;
        box-shadow:0 2px 10px rgba(0,0,0,.25); font-family:"Cascadia Mono",Consolas,"Microsoft YaHei",monospace; }
.bar { background:#2d333b; color:#adbac7; font-size:12px; padding:7px 12px; display:flex; justify-content:space-between;
       font-family:"Microsoft YaHei","Cascadia Mono",sans-serif; }
.bar .meta { color:#768390; }
.body { background:#0d1117; color:#e6edf3; font-size:13px; line-height:1.48; padding:12px 14px 14px;
        white-space:pre-wrap; word-break:break-all; }
.l { min-height:1.48em; }
.cmd { color:#7ee787; font-weight:600; }
.err { color:#ff7b72; font-weight:600; }
.comment { color:#8b949e; }
.cut { color:#d29922; font-style:italic; }
"""


def parse_range(spec: str | None, n: int) -> tuple[int, int]:
    if not spec:
        return 1, n
    a, _, b = spec.partition("-")
    return max(1, int(a or 1)), min(n, int(b or n))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("png")
    ap.add_argument("--title", default="devops-lab (WSL2 Ubuntu 24.04)")
    ap.add_argument("--lines", help="1-based inclusive line range of the log file, e.g. 4-40")
    ap.add_argument("--max-lines", type=int, default=70, help="keep head+tail and mark the cut")
    ap.add_argument("--width", type=int, default=980, help="CSS pixel width of the terminal")
    args = ap.parse_args()

    raw = Path(args.log).read_text(encoding="utf-8", errors="replace").splitlines()
    recorded = next((ln for ln in raw[:3] if ln.startswith("# recorded:")), "")
    stamp = recorded.split("|")[0].replace("# recorded:", "").strip()
    a, b = parse_range(args.lines, len(raw))
    lines = [ANSI.sub("", ln) for ln in raw[a - 1:b]]
    if not args.lines:
        lines = [ln for ln in lines if not ln.startswith(("# transcript:", "# recorded:"))]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()

    rows: list[str] = []
    if args.max_lines and len(lines) > args.max_lines:
        head = args.max_lines * 2 // 3
        tail = args.max_lines - head
        omitted = len(lines) - head - tail
        lines = lines[:head] + [f"\0cut … 中间省略 {omitted} 行输出 …"] + lines[-tail:]

    continuation = False
    for ln in lines:
        if ln.startswith("\0cut"):
            rows.append(f'<div class="l cut">{html.escape(ln[4:])}</div>')
            continue
        cls = ""
        if continuation or ln.startswith("$ "):
            cls = "cmd"
            continuation = ln.endswith("\\")
        elif re.fullmatch(r"\[exit \d+\]", ln):
            cls = "err"
        elif ln.startswith("# "):
            cls = "comment"
        rows.append(f'<div class="l {cls}">{html.escape(ln) or "&nbsp;"}</div>')

    meta = f"终端记录渲染 · recorded {stamp}" if stamp else "终端记录渲染"
    doc = (
        f"<html><head><meta charset='utf-8'><style>{CSS}</style></head><body>"
        f"<div class='term' style='--w:{args.width}px'><div class='bar'><span>{html.escape(args.title)}</span>"
        f"<span class='meta'>{html.escape(meta)}</span></div><div class='body'>{''.join(rows)}</div></div></body></html>"
    )
    out = Path(args.png)
    out.parent.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge")
        page = browser.new_page(device_scale_factor=2, viewport={"width": args.width + 40, "height": 400})
        page.set_content(doc)
        page.locator(".term").screenshot(path=str(out))
        browser.close()
    print(f"{out} ({len(rows)} lines)")


if __name__ == "__main__":
    main()
