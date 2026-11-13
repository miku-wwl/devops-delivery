"""Page make-up helper: for every page that layout_check.py reports as a gap, show the figure that was pushed to the
next page and the sizes of the blocks that follow it in the derived source - enough to write a rule for
v2/manual/pub/layout.txt ("text in the figure block => n": let n blocks of text come before the figure).

  manual/.venv/Scripts/python.exe v2/manual/pub/tools/gaps.py <pdf> [min-fill, default 0.6]

With a higher min-fill (for example 0.82) it also lists the soft gaps that layout_check.py tolerates.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

from pypdf import PdfReader

PUB = Path(__file__).resolve().parents[1]
ROOT = PUB.parents[2]
sys.path.insert(0, str(PUB))
from build_pub import OUT, blocks_of  # noqa: E402

pdf = sys.argv[1]
min_fill = sys.argv[2] if len(sys.argv) > 2 else "0.6"
out = subprocess.run([sys.executable, str(ROOT / "manual" / "tools" / "layout_check.py"), pdf, "--min-fill", min_fill], capture_output=True, text=True,
                     encoding="utf-8", errors="replace").stdout
gaps = [(int(m.group(1)), int(m.group(2))) for m in re.finditer(r"page (\d+): (\d+)% used", out)]
reader = PdfReader(pdf)
blocks = []
for f in sorted(OUT.glob("*.md")):
    blocks += [(f.name, b) for b in blocks_of(f.read_text(encoding="utf-8"))]
norm = lambda s: re.sub(r"\s+", "", s)
for page, used in gaps:
    nxt = norm(reader.pages[page].extract_text() or "")
    hit = None
    for i, (name, b) in enumerate(blocks):
        if b.startswith("![") or b.startswith("```{.mermaid"):
            cap = re.search(r'caption="([^"]{12,40})', b) or re.search(r"!\[([^\]]{12,40})", b)
            if cap and norm(cap.group(1)) in nxt[:2500]:
                hit = i
                break
    if hit is None:
        print(f"p{page} {used}% used: no figure found at the top of the next page")
        continue
    name, b = blocks[hit]
    cap = (re.search(r'caption="([^"]{0,26})', b) or re.search(r"!\[([^\]]{0,26})", b)).group(1)
    follow = []
    for _, nb in blocks[hit + 1:hit + 6]:
        kind = "H" if nb.startswith("#") else "T" if nb.startswith("|") else "F" if nb.startswith(("![", "```")) else "p"
        follow.append(f"{kind}{len(nb)}")
        if kind == "H":
            break
    print(f"p{page} {used}% used ({(100 - used) * 46 * 46 // 100} chars free) | {name[:6]} | {cap} | next: {' '.join(follow)}")
