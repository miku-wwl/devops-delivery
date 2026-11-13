"""The figure registry shared by figures.py (charts from measurements) and diagram_defs.py (hand-laid-out diagrams).

Every generated figure is registered with the chapter that uses it, the evidence files its numbers come from, and
the strings that must be present in the chapter (default) or in an evidence file ("evidence/...::string").
Chapter 0 is the reading guide (pub/front/preface.md).
"""
from __future__ import annotations

from pathlib import Path

PUB = Path(__file__).resolve().parent
MAN = PUB.parent
V2 = MAN.parent
FIG = MAN / "figures"
FIGS: list[dict] = []
CHAPTERS = sorted((MAN / "chapters").glob("*.md"))
PREFACE = PUB / "front" / "preface.md"


def fig(name: str, chapter: int, sources: list[str], check: tuple[str, ...] = (), kind: str = "quoted"):
    """kind: quoted (numbers typed in the figure, held to the text by `check`), parsed (series read from evidence),
    model (a formula), concept (a diagram of a mechanism; any number it shows is listed in `check`)."""
    def deco(fn):
        FIGS.append({"name": name, "chapter": chapter, "sources": sources, "check": check, "kind": kind, "fn": fn})
        return fn
    return deco


def chapter_text(n: int) -> str:
    return (PREFACE if n == 0 else CHAPTERS[n - 1]).read_text(encoding="utf-8")


def ev(rel: str) -> Path:
    return V2 / rel


def rows(rel: str, skip: int = 1) -> list[list[str]]:
    return [l.split() for l in ev(rel).read_text(encoding="utf-8").splitlines()[skip:] if l.strip()]
