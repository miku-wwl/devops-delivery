"""Hand-laid-out diagrams for the Publication Edition.

Boxes, arrows, groups and sequence charts on a fixed 640 px canvas, in the fonts and palette of the data charts
(charts.py). The canvas is printed at scale 1 (the text column is 642 px wide), node text is 10-11 px and edge
labels are 9.5 px, so every label is 7.1-8.3 pt on paper; figcheck.py measures the result.

Why not Mermaid: its automatic layout made long chains wider than the column and tall chains higher than the
figure cap, and the print layout then scaled them down to 3.4-6 pt (review round 1, docs/publication/REVIEW.md).
A fixed canvas with explicit coordinates is more work per diagram and cannot drift into illegibility.
"""
from __future__ import annotations

import math
from pathlib import Path

from charts import C, Svg, esc, tw

# fill, stroke, text colour, dash - the same meaning as the book's four realness labels and its chart palette
KIND = {
    "real": ("#eaf2fb", "#3d7cc9", "#1b2430", None),        # a real component of the lab
    "plain": ("#ffffff", "#9aa5b1", "#1b2430", None),       # neutral step
    "virt": ("#f4f5f7", "#8a94a3", "#3a4553", "4 3"),       # virtual object (KWOK)
    "inject": ("#fdecea", "#c0392b", "#7a1f16", None),      # injected fault or load
    "sim": ("#fff4e0", "#d9730d", "#6b3b05", None),         # simulated / waiting / warning
    "store": ("#e8f5f2", "#0f8a7e", "#0b4f48", None),       # data store
    "ext": ("#f3effb", "#7353ba", "#3d2a73", None),         # outside the cluster
    "good": ("#e6f4ea", "#2e8b57", "#1d5c38", None),
    "bad": ("#fdecea", "#c0392b", "#7a1f16", None),
    "note": ("#fffbe6", "#d4b106", "#5c4a00", None),
    "ghost": ("#ffffff", "#b9c6d4", "#5b6776", "3 3"),
    "dark": ("#0b2545", "#0b2545", "#ffffff", None),
    "zone": ("#f7f9fc", "#b9c6d4", "#46525f", None),        # group background
    "zone2": ("#fbfcfe", "#c9d6e4", "#46525f", "5 4"),      # nested / secondary group
    "warm": ("#fff8ee", "#e6c69a", "#6b3b05", None),        # highlighted group
    "cool": ("#f0f8f6", "#a9d6cd", "#0b4f48", None),
}
EDGE = "#5b6776"


class Box:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h

    def side(self, s, f=0.5):
        if s == "l":
            return (self.x, self.y + self.h * f)
        if s == "r":
            return (self.x + self.w, self.y + self.h * f)
        if s == "t":
            return (self.x + self.w * f, self.y)
        return (self.x + self.w * f, self.y + self.h)

    @property
    def cx(self):
        return self.x + self.w / 2

    @property
    def cy(self):
        return self.y + self.h / 2

    @property
    def right(self):
        return self.x + self.w

    @property
    def bottom(self):
        return self.y + self.h


class Diagram(Svg):
    def __init__(self, h, w=640, title=None):
        super().__init__(w, h)
        if title:
            self.text(12, 19, title, 13, C["ink"], weight="600")

    # ------------------------------------------------------------------ nodes
    def _lines(self, cx, cy, lines, size, color, bold_first, anchor="middle", lh=None):
        lh = lh or size + 3.6
        y = cy - lh * (len(lines) - 1) / 2 + size * 0.36
        for i, line in enumerate(lines):
            small = isinstance(line, tuple)
            s = line[0] if small else line
            sz = size - 0.5 if (small or (bold_first and i > 0)) else size      # details half a pixel under the name
            self.text(cx, y + i * lh, s, sz, color, anchor, "600" if (bold_first and i == 0) else "normal")

    def box(self, x, y, w, h, lines, kind="real", shape="box", size=10.5, bold=True, lh=None) -> Box:
        """lines: str or list; the first line is the node's name (bold), the rest its details."""
        lines = [lines] if isinstance(lines, str) else list(lines)
        fill, stroke, color, dash = KIND[kind]
        d = f' stroke-dasharray="{dash}"' if dash else ""
        cy = y + h / 2
        if shape == "cyl":
            ry = 5.5
            self.e.append(f'<path d="M{x:.1f},{y + ry:.1f} A{w / 2:.1f},{ry} 0 0 1 {x + w:.1f},{y + ry:.1f} V{y + h - ry:.1f} '
                          f'A{w / 2:.1f},{ry} 0 0 1 {x:.1f},{y + h - ry:.1f} Z" fill="{fill}" stroke="{stroke}" stroke-width="1.2"{d}/>')
            self.e.append(f'<path d="M{x:.1f},{y + ry:.1f} A{w / 2:.1f},{ry} 0 0 0 {x + w:.1f},{y + ry:.1f}" fill="none" '
                          f'stroke="{stroke}" stroke-width="1.2"{d}/>')
            cy += ry / 2
        elif shape == "diamond":
            pts = f"{x + w / 2:.1f},{y:.1f} {x + w:.1f},{y + h / 2:.1f} {x + w / 2:.1f},{y + h:.1f} {x:.1f},{y + h / 2:.1f}"
            self.e.append(f'<polygon points="{pts}" fill="{fill}" stroke="{stroke}" stroke-width="1.2"{d}/>')
        else:
            rx = h / 2 if shape == "pill" else 5
            self.e.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx:.1f}" fill="{fill}" '
                          f'stroke="{stroke}" stroke-width="1.2"{d}/>')
        self._lines(x + w / 2, cy, lines, size, color, bold, lh=lh)
        return Box(x, y, w, h)

    def group(self, x, y, w, h, title=None, kind="zone", size=10, anchor="start") -> Box:
        fill, stroke, color, dash = KIND[kind]
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.e.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="7" fill="{fill}" stroke="{stroke}" '
                      f'stroke-width="1"{d}/>')
        if title:
            tx = x + 9 if anchor == "start" else x + w / 2 if anchor == "middle" else x + w - 9
            self.text(tx, y + 15, title, size, color, anchor, "600")
        return Box(x, y, w, h)

    def para(self, x, y, lines, size=9.5, color=C["muted"], anchor="start", weight="normal", lh=None):
        lines = lines.split("\n") if isinstance(lines, str) else lines
        lh = lh or size + 3.5
        for i, line in enumerate(lines):
            self.text(x, y + i * lh, line, size, color, anchor, weight)

    def badge(self, x, y, n, color=C["blue"], r=8):
        self.e.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{color}"/>')
        self.text(x, y + 3.4, n, 9.5, "#ffffff", "middle", "700")

    # ------------------------------------------------------------------ edges
    @staticmethod
    def _pt(p, side):
        if isinstance(p, Box):
            if isinstance(side, tuple):
                return p.side(*side), side[0]
            return p.side(side), side
        return p, side

    def edge(self, a, b, text=None, src=None, dst=None, style="solid", color=EDGE, sw=1.4, via=None, mid=None,
             head=True, tail=False, lp=None, la=None, size=9.5, lcolor=None):
        """An orthogonal connector from a to b (Box or point). src/dst: 'l' 'r' 't' 'b' or (side, fraction).
        via: explicit corner points. mid: x (or y) of the middle segment of a three-segment path.
        text: label, '\\n' for lines; lp=(x, y) places it, otherwise it sits at the middle of the longest segment."""
        if isinstance(a, Box) and isinstance(b, Box) and src is None and dst is None:
            if b.x >= a.right - 1:
                src, dst = "r", "l"
            elif b.right <= a.x + 1:
                src, dst = "l", "r"
            elif b.y >= a.bottom - 1:
                src, dst = "b", "t"
            else:
                src, dst = "t", "b"
        (x1, y1), s1 = self._pt(a, src)
        (x2, y2), s2 = self._pt(b, dst)
        if via is not None:
            pts = [(x1, y1), *via, (x2, y2)]
        else:
            h1 = s1 in ("l", "r") if s1 else abs(x2 - x1) >= abs(y2 - y1)
            h2 = s2 in ("l", "r") if s2 else h1
            if h1 and h2:
                if abs(y1 - y2) < 0.6:
                    pts = [(x1, y1), (x2, y2)]
                else:
                    mx = mid if mid is not None else (x1 + x2) / 2
                    pts = [(x1, y1), (mx, y1), (mx, y2), (x2, y2)]
            elif not h1 and not h2:
                if abs(x1 - x2) < 0.6:
                    pts = [(x1, y1), (x2, y2)]
                else:
                    my = mid if mid is not None else (y1 + y2) / 2
                    pts = [(x1, y1), (x1, my), (x2, my), (x2, y2)]
            elif h1:
                pts = [(x1, y1), (x2, y1), (x2, y2)]
            else:
                pts = [(x1, y1), (x1, y2), (x2, y2)]
        dash = {"solid": None, "dash": "5 4", "dot": "2 3"}[style]

        def trim(p, q, by):
            """Pull the end point q back towards p so the line stops at the base of the arrow head."""
            L = math.hypot(q[0] - p[0], q[1] - p[1]) or 1
            return (q[0] - (q[0] - p[0]) / L * by, q[1] - (q[1] - p[1]) / L * by)

        line = list(pts)
        if head:
            line[-1] = trim(pts[-2], pts[-1], 5)
        if tail:
            line[0] = trim(pts[1], pts[0], 5)
        self.poly(line, color, sw, dash)
        if head:
            self._head(pts[-2], pts[-1], color, sw)
        if tail:
            self._head(pts[1], pts[0], color, sw)
        if text:
            lines = text.split("\n")
            if lp is None:
                seg = max(zip(pts, pts[1:]), key=lambda s: math.hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]))
                mx, my = (seg[0][0] + seg[1][0]) / 2, (seg[0][1] + seg[1][1]) / 2
                if abs(seg[0][1] - seg[1][1]) < 0.6:          # horizontal: centred above the line
                    lp, la = (mx, my - 5 - (len(lines) - 1) * (size + 3)), la or "middle"
                else:                                          # vertical: to the right of the line
                    lp, la = (mx + 6, my + 3 - (len(lines) - 1) * (size + 3) / 2), la or "start"
            for i, s in enumerate(lines):
                self.label(lp[0], lp[1] + i * (size + 3), s, size, lcolor or C["muted"], la or "middle")
        return pts

    def _head(self, p, q, color, sw):
        a = math.atan2(q[1] - p[1], q[0] - p[0])
        L, W = 7.5 + sw, 3.2 + sw * 0.6
        bx, by = q[0] - L * math.cos(a), q[1] - L * math.sin(a)
        l = (bx + W * math.sin(a), by - W * math.cos(a))
        r = (bx - W * math.sin(a), by + W * math.cos(a))
        self.e.append(f'<polygon points="{q[0]:.1f},{q[1]:.1f} {l[0]:.1f},{l[1]:.1f} {r[0]:.1f},{r[1]:.1f}" fill="{color}"/>')

    def cross(self, x, y, color=C["red"], r=6):
        """A cut: the connection here is broken."""
        self.e.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r + 3}" fill="#ffffff"/>')
        self.line(x - r, y - r, x + r, y + r, color, 2.2)
        self.line(x - r, y + r, x + r, y - r, color, 2.2)


def sequence(path, actors, steps, w=640, title=None, number=False, margin=64):
    """A sequence chart. actors: name or (name, kind), '\\n' for two lines.
    steps: ("msg", i, j, text[, "reply"|"async"])  ("self", i, text)  ("note", i, j, text[, kind])
           ("band", title, kind) ... ("end",)  ("gap", px)"""
    names = [a if isinstance(a, tuple) else (a, "real") for a in actors]
    n = len(names)
    xs = [margin + i * (w - 2 * margin) / (n - 1) for i in range(n)]
    two = any("\n" in a for a, _ in names)
    top = 30 if title else 8
    ah = 40 if two else 28
    aw = min(118, (w - 2 * margin) / (n - 1) - 10)

    # first pass: heights
    y = top + ah + 16
    layout = []
    for st in steps:
        kind = st[0]
        if kind == "msg":
            lines = st[3].split("\n")
            y += 13 * len(lines) + 4
            layout.append(y)
            y += 13
        elif kind == "self":
            lines = st[2].split("\n")
            layout.append(y)
            y += max(30, 13 * len(lines) + 12)
        elif kind == "note":
            lines = st[3].split("\n")
            layout.append(y)
            y += 13 * len(lines) + 12 + 9
        elif kind == "band":
            layout.append(y)
            y += 19
        elif kind == "end":
            layout.append(y)
            y += 12
        elif kind == "gap":
            layout.append(y)
            y += st[1]
    h = y + 10
    d = Diagram(h, w, title)

    # bands first (behind everything)
    stack = []
    for st, yy in zip(steps, layout):
        if st[0] == "band":
            stack.append((st, yy))
        elif st[0] == "end":
            (b, y0) = stack.pop()
            fill, stroke, color, _ = KIND[b[2]]
            d.e.append(f'<rect x="10" y="{y0 - 4:.1f}" width="{w - 20}" height="{yy - y0 + 8:.1f}" rx="6" fill="{fill}" '
                       f'stroke="{stroke}" stroke-width="1"/>')
            d.text(19, y0 + 11, b[1], 10, color, weight="600")
    for x in xs:
        d.line(x, top + ah, x, h - 10, "#9aa5b1", 1.0, "4 4")
    for (name, kind), x in zip(names, xs):
        d.box(x - aw / 2, top, aw, ah, name.split("\n"), kind, size=10.5, bold=False)
    k = 0
    bgs = ["#ffffff"]
    for st, yy in zip(steps, layout):
        kind = st[0]
        if kind == "band":
            bgs.append(KIND[st[2]][0])
        elif kind == "end":
            bgs.pop()
        if kind == "msg":
            _, i, j, text = st[:4]
            mode = st[4] if len(st) > 4 else "sync"
            x1, x2 = xs[i], xs[j]
            d.edge((x1, yy), (x2, yy), style="dash" if mode in ("reply", "async") else "solid", color="#3a4553", sw=1.3)
            lines = text.split("\n")
            width = max(tw(s, 9.5) for s in lines)
            off = 21 if number else 7
            if x2 > x1:       # the label starts at the sender and reads in the direction of the arrow
                tx, anchor = min(x1 + off, w - 8 - width), "start"
            else:
                tx, anchor = max(x1 - off, 8 + width), "end"
            for q, s in enumerate(lines):
                d.label(tx, yy - 6 - (len(lines) - 1 - q) * 13, s, 9.5, C["ink"], anchor, bg=bgs[-1])
            if number:
                k += 1
                d.badge(x1 + (11 if x2 > x1 else -11), yy, k, C["blue"], 7)
        elif kind == "self":
            _, i, text = st
            x = xs[i]
            d.poly([(x, yy), (x + 26, yy), (x + 26, yy + 16), (x + 5, yy + 16)], "#3a4553", 1.3)
            d._head((x + 26, yy + 16), (x, yy + 16), "#3a4553", 1.3)
            for q, s in enumerate(text.split("\n")):
                right = x + 34 + tw(s, 9.5) < w - 6
                d.label(x + 33 if right else x - 8, yy + 11 + q * 13, s, 9.5, C["ink"], "start" if right else "end")
        elif kind == "note":
            _, i, j, text = st[:4]
            nk = st[4] if len(st) > 4 else "note"
            lines = text.split("\n")
            width = max(tw(s, 9.5) for s in lines) + 18
            x1, x2 = xs[i] - 8, xs[j] + 8
            if x2 - x1 < width:
                c = (x1 + x2) / 2
                x1, x2 = c - width / 2, c + width / 2
                if x1 < 8:
                    x1, x2 = 8, 8 + width
                if x2 > w - 8:
                    x1, x2 = w - 8 - width, w - 8
            bh = 13 * len(lines) + 10
            d.box(x1, yy, x2 - x1, bh, lines, nk, size=9.5, bold=False, lh=13)
    d.save(path)
    return h
