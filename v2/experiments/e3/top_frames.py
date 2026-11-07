"""Where does the CPU go? Summarise py-spy raw output ("frame;frame;... count" per line).

    python3 top_frames.py profile.collapsed.txt [--seconds S] [--top N]

Expects a profile recorded with --gil --full-filenames (profile.sh), so that every sample is a
moment in which some thread held the GIL, i.e. was running Python (or C code called from it).
Each frame is "function (path:line)". A sample is charged to one component: the innermost frame
that belongs to a named component, so helpers (asyncio, anyio, contextlib, functools, ...) are
charged to whatever called them. A sample whose innermost Python frame is asyncio's run() is
the event loop's own C code (uvloop callbacks, task stepping) and is reported separately. Prints the share of samples per component and per thread kind,
the most expensive functions of our own code, and the top innermost frames (self time).
"""

from __future__ import annotations

import argparse
import re
from collections import Counter

FRAME = re.compile(r"^(?P<fn>.*) \((?P<path>.*?)(?::(?P<line>\d+))?\)$")
SITE = "site-packages/"
LOOP = re.compile(r"^run \(.*asyncio/runners\.py:\d+\)$")

# (component, test on the module path relative to site-packages or the stdlib)
COMPONENTS: list[tuple[str, re.Pattern[str]]] = [
    ("import system (failed imports)", re.compile(r"^<frozen importlib")),
    ("storefront (our code)", re.compile(r"^(app/src/)?storefront/")),
    ("OpenTelemetry instrumentation (ASGI, FastAPI, httpx)", re.compile(r"^opentelemetry/(instrumentation|util)/")),
    ("OpenTelemetry SDK + export (spans, logs)", re.compile(r"^opentelemetry/")),
    ("HTTP client (httpx, httpcore, h11)", re.compile(r"^(httpx|httpcore|h11)/")),
    ("web framework (FastAPI, Starlette, Pydantic)", re.compile(r"^(fastapi|starlette|pydantic|pydantic_core)/")),
    ("HTTP server (uvicorn, httptools)", re.compile(r"^(uvicorn|httptools|uvloop)/")),
    ("database driver (asyncpg)", re.compile(r"^asyncpg/")),
    ("cache client (redis/valkey)", re.compile(r"^(redis|valkey)/")),
    ("messaging (nats)", re.compile(r"^nats/")),
    ("Prometheus client", re.compile(r"^prometheus_client/")),
    ("logging (stdlib)", re.compile(r"^logging/")),
    ("JSON (stdlib)", re.compile(r"^json/")),
    ("garbage collector callbacks, weakrefs", re.compile(r"^(_weakrefset|weakref)\.py")),
]


def rel(path: str) -> str:
    if SITE in path:
        return path.split(SITE, 1)[1]
    m = re.search(r"/lib/python3\.\d+/(.*)$", path)
    if m:
        return m.group(1)
    return path.lstrip("/")


def component(path: str) -> str | None:
    r = rel(path)
    for name, pattern in COMPONENTS:
        if pattern.search(r):
            return name
    return None


def thread_kind(frames: list[str]) -> str:
    if not frames or "threading.py" not in frames[0]:
        return "event loop (main thread)"
    joined = " ".join(frames)
    if "loopwatch" in joined:
        return "watchdog thread (loopwatch)"
    if "opentelemetry" in joined:
        return "OpenTelemetry export threads"
    return "other threads"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--seconds", type=float, default=0)
    ap.add_argument("--top", type=int, default=10)
    a = ap.parse_args()
    stacks: list[tuple[list[str], int]] = []
    for line in open(a.path, encoding="utf-8", errors="replace"):
        line = line.rstrip()
        if line:
            stack, _, count = line.rpartition(" ")
            stacks.append((stack.split(";"), int(count)))
    total = sum(c for _, c in stacks)
    held = f" = GIL held {total / (a.seconds * 100):.0%} of the time" if a.seconds else ""
    print(f"{total} samples with the GIL held{held}")
    if not total:
        return
    by_comp: Counter[str] = Counter()
    by_thread: Counter[str] = Counter()
    ours: Counter[str] = Counter()
    leaf: Counter[str] = Counter()
    for frames, count in stacks:
        by_thread[thread_kind(frames)] += count
        owner = "unattributed (stdlib helpers)"
        if LOOP.search(frames[-1]):  # innermost Python frame is asyncio.run: C code of the loop
            owner = "event loop machinery (uvloop, task scheduling; C code)"
        for f in reversed(frames if owner.startswith("unattributed") else ()):
            m = FRAME.match(f)
            if m and (c := component(m["path"])):
                owner = c
                break
        by_comp[owner] += count
        for f in reversed(frames):
            m = FRAME.match(f)
            if m and component(m["path"]) == "storefront (our code)":
                ours[f"{m['fn']} ({rel(m['path']).removeprefix('app/src/')})"] += count
                break
        m = FRAME.match(frames[-1])
        leaf[f"{m['fn']} ({rel(m['path'])}:{m['line']})" if m else frames[-1]] += count
    print("by thread:")
    for name, c in by_thread.most_common():
        print(f"  {100 * c / total:5.1f} %  {name}")
    print("by component (innermost frame that belongs to one):")
    for name, c in by_comp.most_common():
        print(f"  {100 * c / total:5.1f} %  {name}")
    print(f"our code on the stack, innermost storefront function (top {a.top}):")
    for name, c in ours.most_common(a.top):
        print(f"  {100 * c / total:5.1f} %  {name}")
    print(f"innermost frames, self time (top {a.top}):")
    for name, c in leaf.most_common(a.top):
        print(f"  {100 * c / total:5.1f} %  {name[:120]}")


if __name__ == "__main__":
    main()
