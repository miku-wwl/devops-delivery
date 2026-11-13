"""Build the Publication Edition of volume 2.

  manual/.venv/Scripts/python.exe v2/manual/pub/build_pub.py [--only 4,11] [--html-only] [--out <pdf>]

The chapter sources stay as they are checked (v2/manual/chapters, verify_evidence.py --root v2). This script derives
the book from them, deterministically, into v2/manual/.pubsrc and prints it with manual/tools/build.py:

  1. evidence references (`evidence/eN/...` code spans) become small superscript numbers; the files are listed per
     chapter in appendix D - the text keeps its traceability without carrying file paths;
  2. the "deliverables" table at the head of every chapter moves to appendix C (code and experiment index); the
     paragraph on how real the chapter's experiments are becomes a framed note;
  3. every figure gets a kind class (concept diagram / measured data / screenshot / terminal record / model curve);
     the diagrams are drawn by diagram_defs.py - a Mermaid block, should a chapter contain one, still works and gets
     the book's node classes;
  4. page make-up: the rules of layout.txt (a figure lets the following text come first, or gets a height cap);
     tables whose columns were not sized by hand get widths that follow their content;
  5. front matter (reading guide), exercise answers (appendix A), glossary (appendix B) and the two generated
     appendices are added.
Charts and diagrams are regenerated first (figures.py); `--check` there verifies their numbers.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path

PUB = Path(__file__).resolve().parent
MAN = PUB.parent
V2 = MAN.parent
ROOT = V2.parent
SRC = MAN / "chapters"
OUT = MAN / ".pubsrc"
DEFAULT_PDF = MAN / "dist" / "Enterprise-Platform-SRE-Handbook-Vol2-Publication-Edition.pdf"

CLASSDEFS = """
  classDef real fill:#eaf2fb,stroke:#3d7cc9,color:#1b2430;
  classDef virt fill:#f4f5f7,stroke:#8a94a3,color:#3a4553,stroke-dasharray:4 3;
  classDef inject fill:#fdecea,stroke:#c0392b,color:#7a1f16;
  classDef sim fill:#fff4e0,stroke:#d9730d,color:#6b3b05;
  classDef store fill:#e8f5f2,stroke:#0f8a7e,color:#0b4f48;
  classDef ext fill:#f3effb,stroke:#7353ba,color:#3d2a73;
  classDef good fill:#e6f4ea,stroke:#2e8b57,color:#1d5c38;
  classDef bad fill:#fdecea,stroke:#c0392b,color:#7a1f16;
  classDef note fill:#fffbe6,stroke:#d4b106,color:#5c4a00;
  classDef ghost fill:#ffffff,stroke:#c5d0dc,color:#6b7785,stroke-dasharray:3 3;
  classDef dark fill:#0b2545,stroke:#0b2545,color:#ffffff;"""

EV_FULL = re.compile(r"^evidence/[\w./*{},\-]+$")
EV_SHORT = re.compile(r"^[\w.*\-]+\.(?:log|txt|md|json|jsonl|tsv|csv|yaml|yml|png|pprof|html|svg)$")
MARK = "\x00EV{}\x00"


def exists(rel: str) -> bool:
    if any(ch in rel for ch in "*{"):
        pat = re.sub(r"\{[^}]*\}", "*", rel)
        return any(V2.glob(pat))
    return (V2 / rel).exists()


def evidence_markers(text: str, ch: int, index: dict[str, int]) -> str:
    """Replace evidence code spans with numbered markers; a short file name after a full path on the same line means
    a file in the same directory."""
    out, fenced = [], False
    for line in text.split("\n"):
        if line.startswith("```") or line.startswith("~~~"):
            fenced = not fenced
        if fenced or line.startswith("```") or line.startswith("!["):
            out.append(line)
            continue
        last_dir = None

        def repl(m: re.Match) -> str:
            nonlocal last_dir
            code = m.group(1)
            path = None
            if EV_FULL.match(code):
                last_dir = code.rsplit("/", 1)[0] if "/" in code.rstrip("/") else code
                path = code if exists(code) else None
            elif EV_SHORT.match(code) and last_dir and exists(f"{last_dir}/{code}"):
                path = f"{last_dir}/{code}"
            if path is None:
                return m.group(0)
            return MARK.format(index.setdefault(path, len(index) + 1))

        line = re.sub(r"`([^`\n]+)`", repl, line)
        # parentheses that hold nothing but markers disappear; neighbouring markers merge into one superscript
        sep = r"(?:、|，|,|；|\s|和|与|及)*"
        line = re.sub(rf"（((?:\x00EV\d+\x00{sep})+)）", lambda m: "".join(re.findall(r"\x00EV\d+\x00", m.group(1))), line)
        line = re.sub(rf"\(((?:\x00EV\d+\x00{sep})+)\)", lambda m: "".join(re.findall(r"\x00EV\d+\x00", m.group(1))), line)

        def render(m: re.Match) -> str:
            nums = re.findall(r"\x00EV(\d+)\x00", m.group(0))
            links = ", ".join(f'<a href="#ev-{ch}-{n}">{n}</a>' for n in nums)
            return f'<sup class="ev">[{links}]</sup>'

        line = re.sub(r"(?:\x00EV\d+\x00(?:、)?)+", render, line)
        # "见 [n]" style leftovers read fine; a dangling "（，" or "（）" does not
        line = line.replace("（）", "").replace("（，", "（")
        # a paragraph that held nothing but evidence files (under a table or a figure) becomes a source line
        if re.fullmatch(r'<sup class="ev">\[.*?\]</sup>', line.strip()):
            line = f'<p class="evsrc">原始记录 {line.strip()}</p>'
        out.append(line)
    return "\n".join(out)


def chapter_head(text: str, title: str, code_index: list[str]) -> str:
    """Move the deliverables table (and the acceptance paragraph of chapters 1-3) to the code index; frame the note
    on how real the experiments are; rename the section."""
    m = re.search(r"^## 本章目标与产出.*?\n(.*?)(?=^## )", text, re.M | re.S)
    if not m:
        return text
    body = m.group(1)
    table = "\n".join(l for l in body.split("\n") if l.startswith("|"))
    accept = [l for l in body.split("\n") if l.startswith("**验收标准")]
    rest = [l for l in body.split("\n") if not l.startswith("|") and not l.startswith("**验收标准")]
    rest_text = "\n".join(rest)
    rest_text = re.sub(r"^(本章的[^\n]*`\[(?:真实|注入|虚拟|模拟)\]`[^\n]*)$", r"::: realness\n\1\n:::", rest_text, flags=re.M)
    rest_text = re.sub(r"\n{3,}", "\n\n", rest_text).strip("\n")
    code_index.append(f"## {title} {{.unnumbered .unlisted}}\n\n{table}\n" + ("\n" + "\n\n".join(accept) + "\n" if accept else ""))
    return text[:m.start()] + "## 学习目标\n\n" + rest_text + "\n\n" + text[m.end():]


def figures(text: str) -> str:
    def image(m: re.Match) -> str:
        path = m.group(2)
        if m.group(3):
            return m.group(0)
        name = path.rsplit("/", 1)[-1]
        kind = "shot" if name.startswith(("grafana", "tempo")) else \
            ("model" if name.startswith("model-") else "concept" if name.startswith("concept-") else "data") \
            if path.endswith(".svg") else "term"
        return f"{m.group(1)}({path}){{.{kind}}}"

    text = re.sub(r"^(!\[.*\])\(([^)\s]+)\)(\{[^}]*\})?$", image, text, flags=re.M)

    def mermaid(m: re.Match) -> str:
        body = m.group(2)
        if re.match(r"\s*(?:%%\{.*?\}%%\s*)?(?:flowchart|graph)\b", body):
            body = body.rstrip("\n") + CLASSDEFS + "\n"
        return m.group(1) + body + "```"

    return re.sub(r"^(```(?:mermaid|\{\.mermaid[^\n]*\})\n)(.*?)^```", mermaid, text, flags=re.M | re.S)


def blocks_of(text: str) -> list[str]:
    """Split Markdown into blocks at blank lines, keeping fenced blocks (code, divs) in one piece."""
    out, cur, fence = [], [], None
    for line in text.split("\n"):
        if fence is None and (line.startswith("```") or (line.startswith(":::") and line.strip() != ":::")):
            fence = line[:3]
        elif fence is not None and line.strip() == fence:
            if fence == ":::" and sum(1 for l in cur if l.startswith(":::") and l.strip() != ":::") > \
                    sum(1 for l in cur if l.strip() == ":::") + 1:
                cur.append(line)      # an inner div closed, the outer one is still open
                continue
            fence = None
            cur.append(line)
            continue
        if fence is None and not line.strip():
            if cur:
                out.append("\n".join(cur))
                cur = []
            continue
        cur.append(line)
    if cur:
        out.append("\n".join(cur))
    return out


def apply_layout(text: str, rules: list[tuple[str, int]], used: set[str]) -> str:
    """Page make-up: a figure that does not fit under its paragraph leaves the rest of the page empty. Two rules:
      text in the figure block => n        let the next n blocks of text come first, so they fill that space and the
                                           figure opens the next page (never across a heading);
      text in the figure block => max NN   cap the figure's height at NN mm (class hNN, pub.css) so that it fits."""
    blocks = blocks_of(text)
    moved = False
    for key, n in rules:
        hits = [i for i, b in enumerate(blocks) if key in b and (b.startswith("![") or b.startswith("```{.mermaid"))]
        if len(hits) != 1:
            continue
        used.add(f"{key}=>{n}")
        moved = True
        i = hits[0]
        if n < 0:      # max height: -NN
            b = blocks[i]
            if b.startswith("```{.mermaid"):
                blocks[i] = b.replace("```{.mermaid", f"```{{.mermaid .h{-n}", 1)
            else:
                blocks[i] = re.sub(r"\)\{\.(\w+)\}$", rf"){{.\1 .h{-n}}}", b)
            continue
        j = i
        while j - i < n and j + 1 < len(blocks) and not blocks[j + 1].startswith("#"):
            j += 1
        blocks.insert(j, blocks.pop(i))
    return "\n\n".join(blocks) + "\n" if moved else text


SEP_ROW = re.compile(r"^\|(?:\s*:?-+:?\s*\|)+\s*$")
# text column; cell padding (with a margin); one half-width unit at 9 pt (a little generous: bold headers, digits);
# widest column that still counts as "one short item"
TEXT_MM, PAD_MM, UNIT_MM, SHORT_MM = 178.0, 5.5, 1.8, 32.0


def _units(cell: str) -> int:
    """Printed width of a cell in half-width units (a CJK character counts two), without Markdown markers."""
    s = re.sub(r"`([^`]*)`", r"\1", cell).replace("**", "")
    s = re.sub(r"<[^>]+>", "", s)
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s.strip())


def column_widths(text: str, report: list | None = None) -> str:
    """Pipe tables whose separator row gives every column the same number of dashes get widths that follow their
    content. Pandoc turns the dashes into relative widths, and equal widths give a one-word first column (a time, an
    ID, a number) as much room as a column of sentences - the sentences then wrap into many short lines (review
    round 2, F2-12). A separator row with unequal dashes was sized by hand and is left alone.

    Columns that hold one short item (up to SHORT_MM) get exactly the room they need and never wrap; the rest of
    the text column is shared by the long columns, damped (exponent 0.6) so that the longest does not starve the
    others. A table that fits without wrapping keeps the proportions of its content."""
    lines = text.split("\n")
    out, i, fenced = [], 0, False
    while i < len(lines):
        line = lines[i]
        if line.startswith("```") or line.startswith("~~~"):
            fenced = not fenced
        if fenced or not line.startswith("|") or i + 1 >= len(lines) or not SEP_ROW.match(lines[i + 1]):
            out.append(line)
            i += 1
            continue
        j = i + 2
        while j < len(lines) and lines[j].startswith("|"):
            j += 1
        seps = [c.strip() for c in lines[i + 1].strip().strip("|").split("|")]
        rows = [re.split(r"(?<!\\)\|", l.strip().strip("|")) for l in [line] + lines[i + 2:j]]
        if len({c.count("-") for c in seps}) == 1 and len(seps) > 1 and all(len(r) == len(seps) for r in rows):
            maxw = [max(max(_units(r[k]) for r in rows), 2) for k in range(len(seps))]
            natural = [PAD_MM + UNIT_MM * w for w in maxw]
            if sum(natural) <= TEXT_MM:
                mm = natural
            else:
                short = [n <= SHORT_MM for n in natural]
                rest = TEXT_MM - sum(n for n, s in zip(natural, short) if s)
                weight = [0.0 if s else w ** 0.6 for w, s in zip(maxw, short)]
                if rest < 0.45 * TEXT_MM:       # many short columns: share everything, damped
                    weight = [w ** 0.6 for w in maxw]
                    mm = [TEXT_MM * x / sum(weight) for x in weight]
                else:
                    mm = [n if s else rest * x / sum(weight) for n, s, x in zip(natural, short, weight)]
            counts = [max(3, round(96 * m / sum(mm))) for m in mm]
            sep = "|" + "|".join((":" if c.startswith(":") else "") + "-" * n + (":" if c.endswith(":") else "")
                                 for c, n in zip(seps, counts)) + "|"
            if report is not None:
                report.append((line[:40], maxw, [round(100 * m / sum(mm)) for m in mm]))
            out += [line, sep] + lines[i + 2:j]
        else:
            out += lines[i:j]
        i = j
    return "\n".join(out)


def unnumber(text: str) -> str:
    """Headings of an appendix: no section numbers, and not listed in the table of contents (the bookmarks keep them)."""
    def fix(m: re.Match) -> str:
        attrs = m.group(3)
        return f"{m.group(1)} {m.group(2)} " + (attrs.strip()[:-1] + " .unnumbered .unlisted}" if attrs else "{.unnumbered .unlisted}")

    return re.sub(r"^(#{1,4}) ([^\n{]+?)(\s*\{[^}\n]*\})?$", fix, text, flags=re.M)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="chapter numbers, e.g. 4,11 (a quick partial build)")
    ap.add_argument("--out", default=str(DEFAULT_PDF))
    ap.add_argument("--html-only", action="store_true")
    ap.add_argument("--no-figures", action="store_true")
    ap.add_argument("--show-tables", action="store_true", help="print the column widths chosen for every re-sized table")
    args = ap.parse_args()
    only = {int(x) for x in args.only.split(",") if x}
    tables_sized = 0

    if not args.no_figures:
        sys.path.insert(0, str(PUB))
        import figures as figmod
        print(f"figures: {figmod.generate()} chart(s) written to {figmod.FIG.relative_to(ROOT)}")

    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    write = lambda name, text: (OUT / name).write_bytes(text.encode("utf-8"))
    code_index, ev_index = [], []
    rules, used = [], set()
    if (PUB / "layout.txt").exists():
        for line in (PUB / "layout.txt").read_text(encoding="utf-8").splitlines():
            if "=>" in line and not line.startswith("#"):
                key, n = line.rsplit("=>", 1)
                n = n.strip()
                rules.append((key.strip(), -int(n[3:]) if n.startswith("max") else int(n)))
    chapters = sorted(SRC.glob("*.md"))
    if not only:
        write("00-preface.md", figures((PUB / "front" / "preface.md").read_text(encoding="utf-8")))
    for n, path in enumerate(chapters, 1):
        text = path.read_text(encoding="utf-8")
        title = re.match(r"# (.*?)\s*\{", text).group(1)
        index: dict[str, int] = {}
        text = evidence_markers(text, n, index)
        text = chapter_head(text, f"第 {n} 章　{title}", code_index)
        text = figures(text)
        text = apply_layout(text, rules, used)
        sized: list = []
        text = column_widths(text, sized)
        tables_sized += len(sized)
        if args.show_tables:
            for head, maxw, shares in sized:
                print(f"  table ch{n:<2} {head:<40} content {maxw} -> widths % {shares}")
        ev_index.append((n, title, index))
        if not only or n in only:
            write(path.name, text)
    if not only:
        answers = (MAN / "appendix-src" / "answers.md").read_text(encoding="utf-8")
        answers = re.sub(r"^# [^\n]*\n", "", answers, count=1, flags=re.M) if answers.startswith("# ") else answers
        write("90-answers.md", "# 附录 A　练习参考答案 {#app-answers .unnumbered}\n\n" + unnumber(answers))
        write("91-glossary.md", (PUB / "back" / "glossary.md").read_text(encoding="utf-8"))
        write("92-code-index.md",
              "# 附录 C　代码与实验索引 {#app-code .unnumbered}\n\n"
              "每一章的实现都在实验仓库的 `v2/` 目录下（`github.com/miku-wwl/devops-delivery`，分支 `v2/publication`）。"
              "下表按章列出产出与位置，路径相对于 `v2/`；前三章另附当时的验收记录。\n\n"
              "::: codeindex\n\n" + column_widths("\n".join(code_index)) + "\n:::\n")
        checks = json.loads((MAN / "spot-checks.json").read_text(encoding="utf-8"))
        ev = ["# 附录 D　证据索引 {#app-evidence .unnumbered}\n",
              "正文中的上标数字（如 <sup class=\"ev\">[3]</sup>）是证据编号：每一章单独编号，对应下面列出的原始记录——终端输出、"
              f"查询结果、时间线与复盘。文件都在实验仓库的 `v2/` 目录下，路径相对于 `v2/`。全书另有 {len(checks)} 处具体陈述与这些文件"
              "逐条自动比对（`v2/manual/spot-checks.json`）。\n"]
        for n, title, index in ev_index:
            if index:
                items = "\n".join(f'<p id="ev-{n}-{k}"><span class="n">[{k}]</span><code>{p}</code></p>' for p, k in index.items())
                ev.append(f"**第 {n} 章　{title}**\n\n<div class=\"evlist\">\n{items}\n</div>\n")
        write("93-evidence.md", "\n".join(ev))
    if not only and len(used) != len(rules):
        print(f"layout: rule(s) that matched no single figure: {[k for k, n in rules if f'{k}=>{n}' not in used]}", file=sys.stderr)
    print(f"sources: {len(list(OUT.glob('*.md')))} file(s) in {OUT.relative_to(ROOT)}; layout rules applied: {len(used)}; tables sized by "
          f"content: {tables_sized}; evidence markers: {sum(len(i) for _, _, i in ev_index)} file(s) in "
          f"{sum(1 for _, _, i in ev_index if i)} chapter(s)")

    cmd = [sys.executable, str(ROOT / "manual" / "tools" / "build.py"), "--chapters", str(OUT / "*.md"),
           "--template", str(PUB / "template.html"), "--metadata", str(PUB / "metadata.yaml"), "--math", "mathml",
           "--toc-depth", "2", "--lua-filter", str(PUB / "codebreak.lua"),
           "--out", args.out, "--subject", "Platform engineering, DevOps and SRE: an evidence-based lab handbook (volume 2, Publication Edition)",
           "--keywords", "Kubernetes, GitOps, Argo CD, Istio ambient, capacity planning, HPA, KEDA, multi-tenancy, chaos engineering, "
                         "disaster recovery, release governance, SLO, observability, KWOK, API Priority and Fairness, OpenTofu"]
    if args.html_only:
        cmd.append("--html-only")
        return subprocess.run(cmd, cwd=ROOT).returncode
    rc = subprocess.run(cmd, cwd=ROOT).returncode
    if rc == 0:
        print(f"bookmarks: {fix_outline(Path(args.out))} title(s) cleaned")
    return rc


def fix_outline(pdf: Path) -> int:
    """The PDF's bookmarks: Chromium doubles the text of unnumbered headings and glues the chapter number to the
    title. Rewrite them as "第 N 章　标题" and undo the doubling."""
    from pypdf import PdfReader, PdfWriter
    from pypdf.generic import TextStringObject

    writer = PdfWriter(clone_from=str(pdf))
    fixed = 0

    def walk(node, top: bool) -> None:
        nonlocal fixed
        while node is not None:
            node = node.get_object()
            title = str(node.get("/Title", ""))
            new = title
            half = len(title) // 2
            if len(title) >= 4 and len(title) % 2 == 0 and title[:half] == title[half:]:
                new = title[:half]
            m = re.match(r"^(\d+)\s*(\D.*)$", new)
            if top and m:
                new = f"第 {m.group(1)} 章　{m.group(2)}"
            if new != title:
                node[NameObject("/Title")] = TextStringObject(new)
                fixed += 1
            if "/First" in node:
                walk(node["/First"], False)
            node = node.get("/Next")

    from pypdf.generic import NameObject
    outlines = writer._root_object.get("/Outlines")
    if outlines is not None and "/First" in outlines.get_object():
        walk(outlines.get_object()["/First"], True)
    with open(pdf, "wb") as fh:
        writer.write(fh)
    return fixed


if __name__ == "__main__":
    sys.exit(main())
