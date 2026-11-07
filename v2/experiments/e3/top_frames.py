"""Summarise py-spy collapsed stacks ("frame;frame;frame count" per line).

    python3 top_frames.py profile.collapsed.txt

Prints the total samples, then the top frames by INCLUSIVE share (time spent in the frame or
anything it called) grouped by library, which answers "where does the CPU go?" for a service.
"""

from __future__ import annotations

import re
import sys
from collections import Counter

GROUPS = [
    ("httpx / httpcore / h11 (outgoing HTTP client)", r"/(httpx|httpcore|h11)/"),
    ("opentelemetry (tracing, metrics, logs)", r"/opentelemetry/"),
    ("fastapi / starlette / pydantic (framework)", r"/(fastapi|starlette|pydantic|pydantic_core)/"),
    ("uvicorn / uvloop / httptools (server)", r"/(uvicorn|uvloop|httptools)/"),
    ("prometheus_client (metrics)", r"/prometheus_client/"),
    ("json (encode/decode)", r"/json/|orjson|_json"),
    ("logging", r"/logging/"),
    ("asyncio (event loop)", r"/asyncio/"),
    ("storefront (our code)", r"/storefront/"),
]


def main(path: str) -> None:
    stacks: list[tuple[list[str], int]] = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip()
        if not line:
            continue
        stack, _, count = line.rpartition(" ")
        stacks.append((stack.split(";"), int(count)))
    total = sum(c for _, c in stacks)
    print(f"{total} samples")
    group_incl: Counter[str] = Counter()
    for frames, count in stacks:
        seen = set()
        for name, pattern in GROUPS:
            if any(re.search(pattern, f) for f in frames) and name not in seen:
                group_incl[name] += count
                seen.add(name)
    print("inclusive share by library (a sample can count for several libraries):")
    for name, count in group_incl.most_common():
        print(f"  {100 * count / total:5.1f} %  {name}")
    leaf: Counter[str] = Counter()
    for frames, count in stacks:
        leaf[re.sub(r" \(.*", "", frames[-1])] += count
    print("top 8 leaf frames (self time):")
    for name, count in leaf.most_common(8):
        print(f"  {100 * count / total:5.1f} %  {name[:110]}")


if __name__ == "__main__":
    main(sys.argv[1])
