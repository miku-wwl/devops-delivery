"""Small helpers for scripted edits of the chapter sources (Publication Edition work).

Edits are anchored on exact text and fail loudly when the anchor is missing or ambiguous, so a script can be
re-read later as a record of what changed. Files are read and written as UTF-8 with LF line endings.
"""
from __future__ import annotations

from pathlib import Path

CH = Path(__file__).resolve().parents[2] / "chapters"


class Doc:
    def __init__(self, name: str):
        self.path = next(CH.glob(name + "*")) if not (CH / name).exists() else CH / name
        self.s = self.path.read_bytes().decode("utf-8").replace("\r\n", "\n")
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
        j = self.s.find("\n\n", i)
        j = len(self.s) if j < 0 else j
        self.s = self.s[:j] + "\n\n" + new.strip("\n") + self.s[j:]
        self.n += 1
        return self

    def before(self, anchor: str, new: str) -> "Doc":
        """Insert `new` as its own block before the line that starts with `anchor`."""
        i = self._one("\n" + anchor)
        self.s = self.s[:i + 1] + new.strip("\n") + "\n\n" + self.s[i + 1:]
        self.n += 1
        return self

    def block(self, start: str, new: str) -> "Doc":
        """Replace the fenced block whose opening line starts with `start` (up to its closing fence)."""
        i = self._one("\n" + start)
        j = self.s.index("\n```\n", i + 1) + 5
        self.s = self.s[:i + 1] + new.strip("\n") + "\n" + self.s[j:]
        self.n += 1
        return self

    def save(self) -> None:
        self.path.write_bytes(self.s.encode("utf-8"))
        print(f"{self.path.name}: {self.n} edit(s)")
