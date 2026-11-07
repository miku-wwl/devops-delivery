"""Print a Tempo trace (OTLP JSON from /api/traces/<id>) as an indented tree.

    python3 trace_tree.py trace.json

Each line: start offset from the root, duration, service, span kind, name, and selected
attributes. Gaps between a parent's end and a child's start (the outbox and the stream) become
visible as offsets larger than the parent's duration.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict

KEEP = ("http.route", "http.response.status_code", "db.statement", "messaging.destination.name",
        "order.id", "order.status", "k8s.pod.name")
KIND = {1: "INTERNAL", 2: "SERVER", 3: "CLIENT", 4: "PRODUCER", 5: "CONSUMER"}


def value(v: dict) -> object:
    return next(iter(v.values())) if v else None


def spans_of(doc: dict) -> list[dict]:
    out = []
    for batch in doc.get("batches", doc.get("resourceSpans", [])):
        res = {a["key"]: value(a["value"]) for a in batch.get("resource", {}).get("attributes", [])}
        for scope in batch.get("scopeSpans", batch.get("instrumentationLibrarySpans", [])):
            for s in scope.get("spans", []):
                attrs = {a["key"]: value(a["value"]) for a in s.get("attributes", [])}
                out.append({
                    "id": s["spanId"], "parent": s.get("parentSpanId", ""), "name": s["name"],
                    "kind": KIND.get(s.get("kind"), s.get("kind")) if isinstance(s.get("kind"), int)
                    else str(s.get("kind", "")).replace("SPAN_KIND_", ""),
                    "start": int(s["startTimeUnixNano"]), "end": int(s["endTimeUnixNano"]),
                    "service": res.get("service.name", "?"), "pod": res.get("k8s.pod.name", ""),
                    "attrs": attrs,
                })
    return out


def main(path: str) -> int:
    spans = spans_of(json.load(open(path, encoding="utf-8")))
    if not spans:
        print("no spans")
        return 1
    ids = {s["id"] for s in spans}
    children = defaultdict(list)
    roots = []
    for s in spans:
        (children[s["parent"]] if s["parent"] in ids else roots).append(s)
    t0 = min(s["start"] for s in spans)
    services = sorted({s["service"] for s in spans})
    print(f"{len(spans)} spans, {len(services)} services: {', '.join(services)}; "
          f"total {(max(s['end'] for s in spans) - t0) / 1e6:.1f} ms")

    def walk(s: dict, depth: int) -> None:
        attrs = " ".join(f"{k}={s['attrs'][k]}" for k in KEEP if k in s["attrs"] and k != "db.statement")
        stmt = s["attrs"].get("db.statement")
        if stmt:
            attrs += f" sql={str(stmt)[:48]!r}"
        print(f"{(s['start'] - t0) / 1e6:9.1f} ms {(s['end'] - s['start']) / 1e6:8.1f} ms  "
              f"{'  ' * depth}{s['service']:<9} {s['kind']:<8} {s['name']}  {attrs}".rstrip())
        for c in sorted(children[s["id"]], key=lambda c: c["start"]):
            walk(c, depth + 1)

    for r in sorted(roots, key=lambda r: r["start"]):
        walk(r, 0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
