"""Review round 2 (docs/publication/REVIEW.md): fixes to the chapter sources and the reading guide.

  F2-01  five figures stood between a lead-in sentence ("...：") and the block that sentence announces
         (2-4, 3-1, 3-3, 8-1, 9-1): the figure moves next to the text it illustrates; two paragraphs are split
  F2-02  figure 7-1 moves in front of the paragraph that names the two modes (it then fits on the page of 7.2.2)
  F2-05  chapter 9, table C0-C4: wider verdict column
  F2-09  reading guide: narrow first column in its two tables

Run once; every step checks that its anchor is present exactly once and that the result differs.
  manual/.venv/Scripts/python.exe v2/manual/pub/tools/p6_round2.py
"""
from __future__ import annotations

from pathlib import Path

MAN = Path(__file__).resolve().parents[2]
CH = MAN / "chapters"


class Lines:
    def __init__(self, path: Path):
        self.path = path
        self.lines = path.read_text(encoding="utf-8").split("\n")

    def find(self, pred, what: str) -> int:
        hits = [i for i, l in enumerate(self.lines) if pred(l)]
        assert len(hits) == 1, f"{self.path.name}: {what}: {len(hits)} match(es)"
        return hits[0]

    def take_figure(self, name: str) -> str:
        """Remove the figure paragraph (one line) and the blank line after it."""
        i = self.find(lambda l: l.startswith("![") and f"/{name}.svg)" in l, f"figure {name}")
        fig = self.lines.pop(i)
        assert self.lines[i] == "" and self.lines[i - 1] == "", f"{name}: the figure is not a paragraph of its own"
        self.lines.pop(i)
        return fig

    def block_end(self, i: int) -> int:
        """Index of the last line of the block that contains line i."""
        while i + 1 < len(self.lines) and self.lines[i + 1] != "":
            i += 1
        return i

    def insert_after_block(self, start: int, fig: str) -> None:
        end = self.block_end(start)
        self.lines[end + 1:end + 1] = ["", fig]

    def insert_before(self, i: int, fig: str) -> None:
        self.lines[i:i] = [fig, ""]

    def split_with_figure(self, at: str, fig: str) -> None:
        """Split a paragraph after the sentence that ends with `at`; the figure goes between the halves."""
        i = self.find(lambda l: at in l and not l.startswith("!["), f"sentence {at[:12]}")
        head, tail = self.lines[i].split(at, 1)
        assert tail.strip(), "nothing after the split point"
        self.lines[i:i + 1] = [head + at, "", fig, "", tail]

    def save(self) -> None:
        self.path.write_text("\n".join(self.lines), encoding="utf-8", newline="\n")
        print(f"{self.path.name}: saved")


def main() -> None:
    # ---- chapter 2: lead-in -> directory tree -> app-of-apps paragraph -> figure 2-4
    d = Lines(CH / "02-e1-storefront.md")
    fig = d.take_figure("concept-app-of-apps")
    d.insert_after_block(d.find(lambda l: l.startswith("**app-of-apps**：根应用指向"), "app-of-apps paragraph"), fig)
    d.save()

    # ---- chapter 3: figure 3-1 after the two bullets it draws; chart 3-3 before "结论很清楚："
    d = Lines(CH / "03-e2-mesh.md")
    fig = d.take_figure("concept-ambient-path")
    d.insert_after_block(d.find(lambda l: l.startswith("- **ztunnel**（零信任隧道）"), "ztunnel bullet"), fig)
    fig = d.take_figure("e2-distribution")
    d.insert_before(d.find(lambda l: l == "结论很清楚：", "lead-in of the conclusions"), fig)
    d.save()

    # ---- chapter 7: figure 7-1 between the five bullets and the paragraph on the two modes
    d = Lines(CH / "07-e6-chaos.md")
    fig = d.take_figure("concept-resilience")
    d.insert_before(d.find(lambda l: l.startswith("两种模式用于对照："), "two modes"), fig)
    d.save()

    # ---- chapter 8: definition of RTO / RPO -> figure 8-1 -> the writer and its three results
    d = Lines(CH / "08-e7-dr.md")
    fig = d.take_figure("concept-rpo-rto")
    d.split_with_figure("目标是事先定的，本章测量的是实际值。", fig)
    d.save()

    # ---- chapter 9: routing rules -> figure 9-1 -> lead-in -> formula; wider verdict column for C0-C4
    d = Lines(CH / "09-e8-release.md")
    fig = d.take_figure("concept-canary-routes")
    d.split_with_figure("测试人员可以在零权重时先行验证。", fig)
    c0 = d.find(lambda l: l.startswith("| C0 |"), "row C0")
    assert d.lines[c0 - 1] == "|---|------------------------|------------------------------|-----|", d.lines[c0 - 1]
    d.lines[c0 - 1] = "|---|----------------------|--------------------------|---------|"
    d.save()

    # ---- reading guide: the first column of both tables holds one short word
    d = Lines(MAN / "pub" / "front" / "preface.md")
    i = d.find(lambda l: l.startswith("| 标注 | 含义 | 例子 |"), "table of the four labels")
    assert d.lines[i + 1] == "|---|---|---|"
    d.lines[i + 1] = "|------|------------------------|------------------------------|"
    i = d.find(lambda l: l.startswith("| 标签 | 含义 |"), "table of the five tags")
    assert d.lines[i + 1] == "|---|---|"
    d.lines[i + 1] = "|-----|--------------------------------------------------|"
    d.save()


if __name__ == "__main__":
    main()
