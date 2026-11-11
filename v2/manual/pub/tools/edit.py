"""Small helpers for scripted edits of the chapter sources (Publication Edition work).

Edits are anchored on exact text and fail loudly when the anchor is missing or ambiguous, so a script can be
re-read later as a record of what changed. Files are read and written as UTF-8 with LF line endings.
"""
from __future__ import annotations

from pathlib import Path

CH = Path(__file__).resolve().parents[2] / "chapters"
NL = "\n"
PARA = "\n\n"


def opener(question: str, results: list[str]) -> str:
    """The chapter opener: the engineering question and what was measured."""
    items = NL.join(f"- {r}" for r in results)
    return f"::: opener{NL}::: q{NL}**工程问题**{PARA}{question}{NL}:::{NL}::: k{NL}**实测结论**{PARA}{items}{NL}:::{NL}:::"


def prod(rows: list[tuple[str, str, str]]) -> str:
    """The lab-versus-production table that closes every chapter's limits section."""
    body = NL.join(f"| {a} | {b} | {c} |" for a, b, c in rows)
    return (f"### 从实验环境到生产环境{PARA}::: prod{NL}| 本章的做法 | 生产环境通常的做法 | 差别意味着什么 |{NL}|---|---|---|{NL}"
            + body + f"{NL}:::")


class Doc:
    def __init__(self, name: str):
        self.path = next(CH.glob(name + "*")) if not (CH / name).exists() else CH / name
        self.s = self.path.read_bytes().decode("utf-8").replace("\r\n", NL)
        self.n = 0

    def _one(self, anchor: str) -> int:
        c = self.s.count(anchor)
        if c != 1:
            raise SystemExit(f"{self.path.name}: anchor found {c} times: {anchor[:60]!r}")
        return self.s.index(anchor)

    def replace(self, old: str, new: str) -> "Doc":
        self._one(old)
        self.s = self.s.replace(old, new)
        self.n += 1
        return self

    def after(self, anchor: str, new: str) -> "Doc":
        """Insert `new` as its own block after the paragraph/line that contains `anchor`."""
        i = self._one(anchor)
        j = self.s.find(PARA, i)
        j = len(self.s) if j < 0 else j
        self.s = self.s[:j] + PARA + new.strip(NL) + self.s[j:]
        self.n += 1
        return self

    def before(self, anchor: str, new: str) -> "Doc":
        """Insert `new` as its own block before the line that starts with `anchor`."""
        i = self._one(NL + anchor)
        self.s = self.s[:i + 1] + new.strip(NL) + PARA + self.s[i + 1:]
        self.n += 1
        return self

    def block(self, start: str, new: str) -> "Doc":
        """Replace the fenced block whose opening line starts with `start` (up to its closing fence)."""
        i = self._one(NL + start)
        j = self.s.index(NL + "```" + NL, i + 1) + 5
        self.s = self.s[:i + 1] + new.strip(NL) + NL + self.s[j:]
        self.n += 1
        return self

    def after_block(self, heading: str, k: int, new: str) -> "Doc":
        """Insert `new` after the k-th block (paragraph, table, list) that follows the heading line."""
        i = self._one(NL + heading)
        pos = self.s.index(PARA, i + 1)
        for _ in range(k):
            nxt = self.s.find(PARA, pos + 2)
            pos = len(self.s) if nxt < 0 else nxt
        self.s = self.s[:pos] + PARA + new.strip(NL) + self.s[pos:]
        self.n += 1
        return self

    def wrap_table(self, header: str, cls: str) -> "Doc":
        """Wrap the table whose header line starts with `header` in a fenced div of class `cls`."""
        i = self._one(NL + header) + 1
        j = i
        while self.s.startswith("|", j):
            j = self.s.index(NL, j) + 1
        self.s = self.s[:i] + f"::: {cls}{NL}" + self.s[i:j] + ":::" + NL + self.s[j:]
        self.n += 1
        return self

    def caption(self, marker: str, text: str, cls: str = "") -> "Doc":
        """Give the plain ```mermaid block that contains the unique text `marker` a caption (and extra classes)."""
        i = self._one(marker)
        j = self.s.rfind(NL + "```mermaid" + NL, 0, i)
        if j < 0:
            raise SystemExit(f"{self.path.name}: no plain mermaid fence before {marker[:40]!r}")
        new = "```{.mermaid" + (f" {cls}" if cls else "") + f' caption="{text}"' + "}"
        self.s = self.s[:j + 1] + new + self.s[j + 1 + len("```mermaid"):]
        self.n += 1
        return self

    def save(self) -> None:
        self.path.write_bytes(self.s.encode("utf-8"))
        print(f"{self.path.name}: {self.n} edit(s)")
