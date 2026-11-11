"""Consistency checks of the Publication Edition's chapter sources.

  manual/.venv/Scripts/python.exe v2/manual/pub/pubcheck.py

1. Openers: every number in a chapter's "measured results" must also appear in the chapter's body - the opener only
   repeats what the chapter measures (and the body is held to the evidence by the spot checks).
2. Figures: every diagram and image has a caption; the kinds are counted (concept / data / screenshot / terminal /
   model) - the counts go on the cover and into the acceptance report.
3. Structure: which teaching elements each chapter has.
Exit code 1 when a check fails.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MAN = Path(__file__).resolve().parents[1]
CHAPTERS = sorted((MAN / "chapters").glob("*.md"))
NUM = re.compile(r"\d+(?:\.\d+)?")


def main() -> int:
    bad = 0
    totals = {"concept": 0, "data": 0, "shot": 0, "term": 0, "model": 0}
    print("chapter                 opener  figures (concept/data/shot/term/model)  limits prod faq exercises summary")
    for n, path in enumerate(CHAPTERS, 1):
        s = path.read_text(encoding="utf-8")
        m = re.search(r"^::: opener\n(.*?)^:::\n:::$", s, re.M | re.S)
        problems = []
        if not m:
            problems.append("no opener")
            body, opener = s, ""
        else:
            opener, body = m.group(1), s[:m.start()] + s[m.end():]
        # numbers of the opener, with thousands written as "211 350" joined
        for tok in NUM.findall(re.sub(r"(?<=\d) (?=\d{3}\b)", "", opener)):
            plain = body.replace(" ", " ")
            joined = re.sub(r"(?<=\d) (?=\d{3}\b)", "", plain)
            if not re.search(rf"(?<![\d.]){re.escape(tok)}(?![\d])", joined):
                problems.append(f"opener number not in the body: {tok}")
        kinds = dict.fromkeys(totals, 0)
        for fence in re.findall(r"^```(mermaid|\{\.mermaid[^\n]*\})$", s, re.M):
            if "caption=" not in fence:
                problems.append("a mermaid diagram without a caption")
            kinds["data" if ".data" in fence else "concept"] += 1
        for alt, src in re.findall(r"^!\[(.*?)\]\(([^)\s]+)\)", s, re.M):
            if len(alt) < 20:
                problems.append(f"image without a real caption: {src}")
            name = src.rsplit("/", 1)[-1]
            kind = "shot" if name.startswith(("grafana", "tempo")) else \
                ("model" if name.startswith("model-") else "concept" if name.startswith("concept-") else "data") \
                if src.endswith(".svg") else "term"
            kinds[kind] += 1
        for k, v in kinds.items():
            totals[k] += v
        has = lambda pat: "yes" if re.search(pat, s, re.M) else " - "
        print(f"{n:2} {path.name[3:22]:20} {'yes' if m else 'NO ':6}  {sum(kinds.values()):2} "
              f"({kinds['concept']}/{kinds['data']}/{kinds['shot']}/{kinds['term']}/{kinds['model']})".ljust(52)
              + f"{has(r'^## 局限'):6} {has(r'^::: prod'):4} {has(r'^## 常见问题'):4} {has(r'^## 练习'):9} {has(r'^## 本章小结|^## 第二册的边界')}")
        for p in problems:
            print(f"      FAIL {p}")
        bad += len(problems)
    total = sum(totals.values())
    print(f"figures in chapters: {total} = concept {totals['concept']}, measured data {totals['data']}, screenshots {totals['shot']}, "
          f"terminal records {totals['term']}, model curves {totals['model']}  (+1 book map in the reading guide)")
    print(f"RESULT: {'FAIL' if bad else 'PASS'}" + (f" - {bad} problem(s)" if bad else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
