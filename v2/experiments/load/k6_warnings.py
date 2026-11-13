"""Collapse k6's per-request "Request Failed" warnings in a k6 output or a transcript.

    python3 k6_warnings.py <file> [<file> ...]     (rewrites each file in place)

A run against a failing system prints one warning per failed request: tens of thousands of
near-identical lines (a 2-minute step at 180 iterations/s produced 6 MB). Every run of
consecutive warnings is replaced by its first three lines and one summary line with the number
of warnings by error (addresses and ports normalised), so the evidence keeps the facts and stays
small. Files without such warnings are left untouched.
"""

from __future__ import annotations

import re
import sys
from collections import Counter

WARN = re.compile(r'level=warning msg="Request Failed" error="(?P<err>.*)"\s*$')
ADDR = re.compile(r"\d+\.\d+\.\d+\.\d+(:\d+)?")
KEEP = 3


def kind(err: str) -> str:
    # 'Get "http://.../api/products?limit=20": EOF' -> 'EOF'
    tail = err.rsplit('": ', 1)[-1] if '": ' in err else err
    return ADDR.sub("ADDR", tail.replace('\\"', '"'))


def collapse(lines: list[str]) -> tuple[list[str], int]:
    out: list[str] = []
    run: list[str] = []
    dropped = 0

    def flush() -> None:
        nonlocal dropped
        if not run:
            return
        out.extend(run[:KEEP])
        if len(run) > KEEP:
            counts = Counter(kind(WARN.search(x)["err"]) for x in run)
            detail = ", ".join(f"{n} {k}" for k, n in counts.most_common())
            out.append(f"[{len(run) - KEEP} more 'Request Failed' warnings collapsed; "
                       f"all {len(run)} by error: {detail}]\n")
            dropped += len(run) - KEEP
        run.clear()

    for line in lines:
        if WARN.search(line):
            run.append(line)
        else:
            flush()
            out.append(line)
    flush()
    return out, dropped


def main(paths: list[str]) -> None:
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        out, dropped = collapse(lines)
        if dropped:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.writelines(out)
            print(f"{path}: {dropped} warning lines collapsed, {len(lines)} -> {len(out)} lines")


if __name__ == "__main__":
    main(sys.argv[1:])
