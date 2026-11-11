"""Dependency-free SVG charts for the Publication Edition.

Every chart is drawn from numbers measured in the lab; figures.py records, for each figure, where the
numbers come from and checks them against the chapter text or the evidence files. One visual language
for the whole book: same fonts, palette, grid and annotation style.
"""
from __future__ import annotations

import math
from pathlib import Path

FONT = "'Segoe UI','Microsoft YaHei','Noto Sans SC',sans-serif"
C = {
    "ink": "#1b2430", "muted": "#5b6776", "grid": "#e6ebf0", "axis": "#9aa5b1",
    "blue": "#1f6fb2", "teal": "#0f8a7e", "orange": "#d9730d", "red": "#c0392b", "purple": "#7353ba",
    "gray": "#8a94a3", "green": "#2e8b57",
    "lblue": "#cfe3f6", "lteal": "#cdeae6", "lorange": "#f9e1c4", "lred": "#f6d3cf", "lgray": "#e9edf2",
    "lgreen": "#d5ecdd", "lpurple": "#e3dbf5",
}


def tw(s, size=11.0) -> float:
    """Rough text width: CJK glyphs are square, Latin about 0.55 em."""
    return sum(size * (1.0 if ord(ch) > 0x2E7F else 0.55) for ch in str(s))


def esc(s) -> str:
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def fmt(v) -> str:
    if abs(v - round(v)) < 1e-9:
        return f"{int(round(v)):,}".replace(",", " ") if abs(v) >= 10000 else str(int(round(v)))
    return f"{v:.2f}".rstrip("0").rstrip(".")


def ticks(lo: float, hi: float, n: int = 5) -> list[float]:
    span = hi - lo
    mag = 10 ** math.floor(math.log10(span / n))
    step = mag
    for m in (1, 2, 2.5, 5, 10):
        step = m * mag
        if span / step <= n + 0.5:
            break
    v, out = math.ceil(lo / step - 1e-9) * step, []
    while v <= hi + 1e-9:
        out.append(round(v, 10))
        v += step
    return out


class Svg:
    def __init__(self, w: float, h: float):
        self.w, self.h, self.e = w, h, []

    def rect(self, x, y, w, h, fill, stroke="none", rx=0, sw=1, opacity=None):
        o = f' opacity="{opacity}"' if opacity is not None else ""
        self.e.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{max(w, 0):.1f}" height="{max(h, 0):.1f}" fill="{fill}" '
                      f'stroke="{stroke}" stroke-width="{sw}" rx="{rx}"{o}/>')

    def line(self, x1, y1, x2, y2, stroke=C["axis"], sw=1.0, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.e.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

    def poly(self, pts, stroke, sw=2.0, dash=None, fill="none", opacity=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        o = f' fill-opacity="{opacity}"' if opacity is not None else ""
        p = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        self.e.append(f'<polyline points="{p}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" '
                      f'stroke-linejoin="round" stroke-linecap="round"{d}{o}/>')

    def circle(self, x, y, r, fill, stroke="#fff", sw=1.2):
        self.e.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')

    def text(self, x, y, s, size=11.0, fill=C["ink"], anchor="start", weight="normal", rotate=None):
        r = f' transform="rotate({rotate} {x:.1f} {y:.1f})"' if rotate else ""
        self.e.append(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" '
                      f'font-weight="{weight}"{r}>{esc(s)}</text>')

    def label(self, x, y, s, size=10.5, fill=C["ink"], anchor="start", weight="normal"):
        """Text on a white halo, readable on top of lines and bars."""
        w = tw(s, size) + 6
        x0 = x - 3 if anchor == "start" else x - w + 3 if anchor == "end" else x - w / 2
        self.rect(x0, y - size + 1, w, size + 4, "#ffffff", rx=2, opacity=0.86)
        self.text(x, y, s, size, fill, anchor, weight)

    def save(self, path: Path) -> None:
        body = "\n".join(self.e)
        Path(path).write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w:.0f} {self.h:.0f}" width="{self.w:.0f}" '
            f'height="{self.h:.0f}" font-family="{FONT}">\n<rect width="100%" height="100%" fill="#ffffff"/>\n{body}\n</svg>\n',
            encoding="utf-8", newline="\n")


def _legend(s: Svg, items, x, y):
    for name, color, kind in items:
        if kind == "bar":
            s.rect(x, y - 9, 12, 10, color, rx=2)
        else:
            s.line(x, y - 4, x + 18, y - 4, color, 2.4, "5 3" if kind == "dash" else None)
        off = 16 if kind == "bar" else 23
        s.text(x + off, y, name, 10.5, C["muted"])
        x += off + tw(name, 10.5) + 18


def _frame(s: Svg, title, ml, mt, pw, ph, yt, Y, xlabel, ylabel, yfmt=fmt):
    s.text(ml - 44 if ml > 60 else 12, 19, title, 13, C["ink"], weight="600")
    for v in yt:
        s.line(ml, Y(v), ml + pw, Y(v), C["grid"])
        s.text(ml - 7, Y(v) + 3.5, yfmt(v), 10, C["muted"], "end")
    s.line(ml, mt + ph, ml + pw, mt + ph, C["axis"])
    if xlabel:
        s.text(ml + pw / 2, mt + ph + 34, xlabel, 10.5, C["muted"], "middle")
    if ylabel:
        s.text(14, mt + ph / 2, ylabel, 10.5, C["muted"], "middle", rotate=-90)


def line_chart(path, title, series, xlabel="", ylabel="", xlim=None, ylim=None, w=640, h=320, hlines=(), vlines=(),
               bands=(), notes=(), xticks=None, yticks=None, xfmt=fmt, yfmt=fmt):
    """series: dict(name, color, pts=[(x, y)], dash, step, marker, label)   hlines/vlines: (value, color, text)
    bands: (x_from, x_to, color, text)   notes: (x, y, text, dx, dy[, color])"""
    ml, mr, mt, mb = 62, 24, 52, 46
    pw, ph = w - ml - mr, h - mt - mb
    xs = [x for sr in series for x, _ in sr["pts"]]
    ys = [y for sr in series for _, y in sr["pts"]]
    x0, x1 = xlim or (min(xs), max(xs))
    y0, y1 = ylim or (0, max(ys) * 1.08)
    X = lambda x: ml + (x - x0) / (x1 - x0) * pw
    Y = lambda y: mt + ph - (y - y0) / (y1 - y0) * ph
    s = Svg(w, h)
    for a, b, color, text in bands:
        s.rect(X(a), mt, X(b) - X(a), ph, color, opacity=0.5)
        if text:
            s.text((X(a) + X(b)) / 2, mt + 12, text, 10, C["muted"], "middle")
    _frame(s, title, ml, mt, pw, ph, yticks or ticks(y0, y1), Y, xlabel, ylabel, yfmt)
    for v in xticks or ticks(x0, x1, 8):
        s.line(X(v), mt + ph, X(v), mt + ph + 4, C["axis"])
        s.text(X(v), mt + ph + 16, xfmt(v), 10, C["muted"], "middle")
    for v, color, text in hlines:
        s.line(ml, Y(v), ml + pw, Y(v), color, 1.3, "6 4")
        s.label(ml + pw - 4, Y(v) - 5, text, 10, color, "end")
    for v, color, text in vlines:
        s.line(X(v), mt, X(v), mt + ph, color, 1.3, "4 3")
        s.label(X(v) + 4, mt + 11, text, 10, color)
    for sr in series:
        pts = sr["pts"]
        if sr.get("step"):
            pts = [p for (a, ya), (b, _) in zip(pts, pts[1:]) for p in ((a, ya), (b, ya))] + [pts[-1]]
        s.poly([(X(x), Y(y)) for x, y in pts], sr["color"], sr.get("sw", 2.2), sr.get("dash"))
        if sr.get("marker"):
            for x, y in sr["pts"]:
                s.circle(X(x), Y(y), 3, sr["color"])
        if sr.get("label"):
            x, y = sr["pts"][-1]
            s.label(min(X(x) + 5, w - tw(sr["label"], 10) - 4), Y(y) - 6, sr["label"], 10, sr["color"], weight="600")
    for n in notes:
        x, y, text, dx, dy = n[:5]
        color = n[5] if len(n) > 5 else C["ink"]
        s.line(X(x), Y(y), X(x) + dx, Y(y) + dy, color, 0.9)
        s.circle(X(x), Y(y), 2.6, color)
        s.label(X(x) + dx + (4 if dx >= 0 else -4), Y(y) + dy + 4, text, 10, color, "start" if dx >= 0 else "end")
    _legend(s, [(sr["name"], sr["color"], "dash" if sr.get("dash") else "line") for sr in series if sr.get("name")], ml, 40)
    s.save(path)


def bar_chart(path, title, cats, series, ylabel="", ylim=None, w=640, h=300, vfmt=fmt, hlines=(), yticks=None,
              stacked=False, notes=(), yfmt=fmt, labels=True):
    """Grouped (or stacked) vertical bars. series: dict(name, color, vals)   notes: (cat index, y, text)"""
    ml, mr, mt, mb = 62, 20, 52, 40
    pw, ph = w - ml - mr, h - mt - mb
    tops = [sum(sr["vals"][i] or 0 for sr in series) for i in range(len(cats))] if stacked else \
        [v for sr in series for v in sr["vals"] if v is not None]
    y0, y1 = ylim or (0, max(tops) * 1.14)
    Y = lambda y: mt + ph - (y - y0) / (y1 - y0) * ph
    s = Svg(w, h)
    _frame(s, title, ml, mt, pw, ph, yticks or ticks(y0, y1), Y, "", ylabel, yfmt)
    gw = pw / len(cats)
    k = 1 if stacked else len(series)
    bw = min(46, gw * 0.78 / k)
    for i, cat in enumerate(cats):
        cx = ml + gw * (i + 0.5)
        base = y0
        for j, sr in enumerate(series):
            v = sr["vals"][i]
            if v is None:
                continue
            x = cx - bw / 2 if stacked else cx - bw * k / 2 + j * bw
            s.rect(x + 1, Y(base + v if stacked else v), bw - 2, Y(base if stacked else y0) - Y(base + v if stacked else v),
                   sr["color"], rx=2)
            if labels:
                s.text(x + bw / 2, Y(base + v if stacked else v) - 4, vfmt(v), 9.5, C["ink"], "middle")
            if stacked:
                base += v
        for n, part in enumerate(str(cat).split("\n")):
            s.text(cx, mt + ph + 15 + n * 12, part, 10, C["muted"], "middle")
    for v, color, text in hlines:
        s.line(ml, Y(v), ml + pw, Y(v), color, 1.3, "6 4")
        s.label(ml + pw - 4, Y(v) - 5, text, 10, color, "end")
    for i, y, text in notes:
        s.label(ml + gw * (i + 0.5), Y(y), text, 10, C["red"], "middle", "600")
    _legend(s, [(sr["name"], sr["color"], "bar") for sr in series if sr.get("name")], ml, 40)
    s.save(path)


def hbar_chart(path, title, rows, xlabel="", xlim=None, w=640, row_h=27, log=False, vline=None, label_w=None,
               legend=()):
    """Horizontal bars, one per row: (label, value, color, value text). log=True for values over decades."""
    lw = label_w or max(tw(r[0], 10.5) for r in rows) + 14
    ml, mr, mt, mb = lw + 10, 86, 48 if legend else 34, 36
    pw, ph = w - ml - mr, row_h * len(rows)
    h = mt + ph + mb
    vals = [r[1] for r in rows if r[1] is not None]
    x0, x1 = xlim or ((min(vals) / 2 if log else 0), max(vals) * (1.6 if log else 1.05))
    T = (lambda v: math.log10(v)) if log else (lambda v: v)
    X = lambda v: ml + (T(v) - T(x0)) / (T(x1) - T(x0)) * pw
    s = Svg(w, h)
    s.text(12, 19, title, 13, C["ink"], weight="600")
    tk = [10 ** e for e in range(math.ceil(math.log10(x0)), math.floor(math.log10(x1)) + 1)] if log else ticks(x0, x1, 6)
    for v in tk:
        s.line(X(v), mt, X(v), mt + ph, C["grid"])
        s.text(X(v), mt + ph + 15, fmt(v), 10, C["muted"], "middle")
    for i, (label, v, color, vt) in enumerate(rows):
        y = mt + i * row_h
        s.text(ml - 8, y + row_h / 2 + 4, label, 10.5, C["ink"], "end")
        if v is not None:
            s.rect(ml, y + 5, X(v) - ml, row_h - 10, color, rx=2)
            s.text(X(v) + 6, y + row_h / 2 + 4, vt, 10, C["ink"])
        else:
            s.text(ml + 6, y + row_h / 2 + 4, vt, 10, C["muted"])
    if vline:
        v, color, text = vline
        s.line(X(v), mt - 4, X(v), mt + ph, color, 1.3, "5 3")
        s.label(X(v) + 4, mt + 8, text, 10, color)
    s.line(ml, mt, ml, mt + ph, C["axis"])
    if xlabel:
        s.text(ml + pw / 2, mt + ph + 31, xlabel, 10.5, C["muted"], "middle")
    _legend(s, [(n, c, "bar") for n, c in legend], ml, 38)
    s.save(path)


def timeline(path, title, lanes, xlim, xlabel="", w=640, lane_h=30, events=(), xticks=None, xfmt=fmt, bands=(),
             legend=()):
    """lanes: (name, [(t0, t1, color, text)])   events: (t, text, color) drawn as flags above the lanes."""
    lw = max(tw(n, 10.5) for n, _ in lanes) + 16
    rows = 1 + max((i % 3 for i in range(len(events))), default=-1)
    ml, mr, mt, mb = lw + 8, 22, 34 + (14 if legend else 0) + rows * 15, 40
    pw, ph = w - ml - mr, lane_h * len(lanes)
    h = mt + ph + mb
    x0, x1 = xlim
    X = lambda t: ml + (t - x0) / (x1 - x0) * pw
    s = Svg(w, h)
    s.text(12, 19, title, 13, C["ink"], weight="600")
    for a, b, color, text in bands:
        s.rect(X(a), mt, X(b) - X(a), ph, color, opacity=0.5)
        if text:
            s.text((X(a) + X(b)) / 2, mt + ph + 28, text, 10, C["muted"], "middle")
    for v in xticks or ticks(x0, x1, 8):
        s.line(X(v), mt, X(v), mt + ph, C["grid"])
        s.text(X(v), mt + ph + 15, xfmt(v), 10, C["muted"], "middle")
    for i, (name, bars) in enumerate(lanes):
        y = mt + i * lane_h
        s.text(ml - 8, y + lane_h / 2 + 4, name, 10.5, C["ink"], "end")
        s.line(ml, y + lane_h, ml + pw, y + lane_h, C["grid"])
        for t0, t1, color, text in bars:
            bwid = max(X(t1) - X(t0), 2)
            s.rect(X(t0), y + 6, bwid, lane_h - 12, color, rx=3)
            if text:
                inside = tw(text, 9.5) + 8 < bwid
                s.text(X(t0) + 5 if inside else X(t1) + 5, y + lane_h / 2 + 3.5, text, 9.5,
                       "#ffffff" if inside and color not in (C["lblue"], C["lteal"], C["lorange"], C["lred"], C["lgray"], C["lgreen"], C["lpurple"]) else C["ink"])
    for i, (t, text, color) in enumerate(events):
        ty = mt - 6 - (i % 3) * 15
        s.line(X(t), ty + 3, X(t), mt + ph, color, 1.1, "3 3")
        right = X(t) + tw(text, 10) + 10 < w
        s.label(X(t) + (4 if right else -4), ty, text, 10, color, "start" if right else "end", "600")
    s.line(ml, mt + ph, ml + pw, mt + ph, C["axis"])
    if xlabel:
        s.text(ml + pw / 2, mt + ph + (31 if not any(b[3] for b in bands) else 42), xlabel, 10.5, C["muted"], "middle")
    _legend(s, [(n, c, "bar") for n, c in legend], ml, 38)
    s.save(path)
