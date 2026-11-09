#!/usr/bin/env python3
"""The kubelet's memory-eviction ranking of the pods on one node, and its admission headroom.

    python3 evict_rank.py NODE_JSON PODS_JSON SUMMARY_JSON [--top N] [--need MIB]

Inputs: `kubectl get node X -o json`, `kubectl get pods -A --field-selector spec.nodeName=X -o json`
and the node's summary API (`/api/v1/nodes/X/proxy/stats/summary`).

Under memory pressure the kubelet (pkg/kubelet/eviction, rankMemoryPressure) orders pods by
  1. whether the pod's working set exceeds its memory request (those first),
  2. priority (lower first),
  3. working set minus request (larger first).
The QoS class is not a key; it only follows from the requests (a BestEffort pod requests 0, a
Guaranteed pod cannot use more than its request). Critical pods are never evicted.

Also prints the node's allocatable memory and the memory requested by its non-terminated pods:
the kubelet's own admission check rejects a pod that does not fit (reason OutOfmemory), even
when the pod was bound with nodeName and the scheduler never saw it. With --need, exits 3 when
less than MIB is free for admission.
"""

import argparse
import json
import sys

UNITS = {"Ki": 2**10, "Mi": 2**20, "Gi": 2**30, "Ti": 2**40, "k": 1e3, "M": 1e6, "G": 1e9, "T": 1e12, "m": 1e-3}


def qty(s: str) -> float:
    for suf in sorted(UNITS, key=len, reverse=True):
        if s.endswith(suf):
            return float(s[: -len(suf)]) * UNITS[suf]
    return float(s)


def mib(b: float) -> float:
    return b / 2**20


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("node")
    ap.add_argument("pods")
    ap.add_argument("summary")
    ap.add_argument("--top", type=int, default=8)
    ap.add_argument("--need", type=float, default=0, help="MiB that must be free for admission")
    a = ap.parse_args()
    with open(a.node) as f:
        node = json.load(f)
    with open(a.pods) as f:
        pods = json.load(f)
    with open(a.summary) as f:
        summary = json.load(f)
    ws = {
        (p["podRef"]["namespace"], p["podRef"]["name"]): (p.get("memory") or {}).get("workingSetBytes", 0)
        for p in summary.get("pods", [])
    }
    rows, requested = [], 0.0
    for p in pods["items"]:
        if p["status"].get("phase") in ("Succeeded", "Failed"):
            continue
        req = sum(qty(c.get("resources", {}).get("requests", {}).get("memory", "0")) for c in p["spec"]["containers"])
        requested += req
        key = (p["metadata"]["namespace"], p["metadata"]["name"])
        use = ws.get(key, 0)
        rows.append((use > req, p["spec"].get("priority", 0), use - req, key, use, req, p["status"].get("qosClass", "?")))
    rows.sort(key=lambda r: (not r[0], r[1], -r[2]))
    alloc = qty(node["status"]["allocatable"]["memory"])
    mem = summary["node"]["memory"]
    print(f"  node working set {mib(mem['workingSetBytes']):.0f} MiB, memory.available {mib(mem['availableBytes']):.0f} MiB")
    free = alloc - requested
    print(
        f"  allocatable {mib(alloc):.0f} MiB, requested by non-terminated pods {mib(requested):.0f} MiB,"
        f" free for admission {mib(free):.0f} MiB"
    )
    print(f"  {'rank':>4}  {'pod':56s} {'QoS':10s} {'priority':>10s} {'ws MiB':>7s} {'req MiB':>7s} {'ws-req':>6s}")
    for i, (_, prio, over, (ns, name), use, req, qos) in enumerate(rows[: a.top], 1):
        print(f"  {i:4d}  {ns + '/' + name:56s} {qos:10s} {prio:10d} {mib(use):7.0f} {mib(req):7.0f} {mib(over):6.0f}")
    return 3 if mib(free) < a.need else 0


if __name__ == "__main__":
    sys.exit(main())
