"""Resource and queueing figures for one time window, from Prometheus (via the API server proxy).

    python3 window_stats.py <start-iso> <end-iso> [--json out.json]

Per storefront service: request rate, CPU cores, CPU milliseconds per request (the "service
demand" D of the utilization law U = X * D), busiest pod's CPU, mean requests in flight (for
Little's law N = X * R), event-loop lag p99 and DB-pool wait p95. Per worker node: CPU cores of
all containers on it. Platform components: waypoint, ztunnels,
OTel collector, Tempo, PostgreSQL. Run on the WSL host (python3 3.12, stdlib only).
"""

from __future__ import annotations

import json
import subprocess
import sys
import urllib.parse
from datetime import datetime

PROXY = "/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query"
NS = 'namespace="storefront"'


def query(expr: str, at: datetime) -> list[dict]:
    path = f"{PROXY}?time={at.timestamp():.0f}&query={urllib.parse.quote(expr)}"
    out = subprocess.run(["kubectl", "get", "--raw", path], capture_output=True, text=True, check=True).stdout
    return json.loads(out)["data"]["result"]


def by(results: list[dict], label: str) -> dict[str, float]:
    return {r["metric"].get(label, "?"): float(r["value"][1]) for r in results}


def window(start: datetime, end: datetime) -> dict:
    w = f"{int((end - start).total_seconds())}s"
    rate = by(query(f"sum by (service) (rate(http_server_requests_total{{{NS}}}[{w}]))", end), "service")
    cpu = by(query(f'sum by (service) (label_replace(rate(container_cpu_usage_seconds_total{{{NS},container="app"}}[{w}]),'
                   f' "service", "$1", "pod", "(.+)-[^-]+-[^-]+"))', end), "service")
    cpu_max = by(query(f'max by (service) (label_replace(rate(container_cpu_usage_seconds_total{{{NS},container="app"}}[{w}]),'
                       f' "service", "$1", "pod", "(.+)-[^-]+-[^-]+"))', end), "service")
    inflight = by(query(f"sum by (service) (avg_over_time(http_server_inflight_requests{{{NS}}}[{w}]))", end), "service")
    lag = by(query(f"histogram_quantile(0.99, sum by (service, le) (rate(event_loop_lag_seconds_bucket{{{NS}}}[{w}])))", end), "service")
    pool = by(query(f"histogram_quantile(0.95, sum by (service, le) (rate(db_pool_acquire_seconds_bucket{{{NS}}}[{w}])))", end), "service")
    # cAdvisor's root-cgroup series (id="/") are not kept by kube-prometheus-stack; the sum over
    # all containers of a node is used instead (it leaves out kubelet and containerd themselves)
    node = by(query(f'sum by (node) (rate(container_cpu_usage_seconds_total{{container!="",pod!="",node=~"ent-worker.*"}}[{w}]))', end), "node")
    plat_expr = (f'sum by (component) (label_replace(rate(container_cpu_usage_seconds_total{{container!="",container!="POD",'
                 f'pod=~"waypoint.*|ztunnel.*|otel-collector.*|tempo.*|pg-main.*|prometheus-kps.*"}}[{w}]),'
                 f' "component", "$1", "pod", "(waypoint|ztunnel|otel-collector|tempo|pg-main|prometheus-kps).*"))')
    plat = by(query(plat_expr, end), "component")
    services = {}
    for svc in sorted(set(rate) | set(cpu)):
        x, c = rate.get(svc, 0.0), cpu.get(svc, 0.0)
        services[svc] = {"req_per_s": round(x, 1), "cpu_cores": round(c, 3),
                         "cpu_ms_per_req": round(1000 * c / x, 2) if x else None,
                         "busiest_pod_cores": round(cpu_max.get(svc, 0.0), 3),
                         "inflight": round(inflight.get(svc, 0.0), 2),
                         "loop_lag_p99_ms": round(1000 * lag[svc], 1) if svc in lag and lag[svc] == lag[svc] else None,
                         "pool_wait_p95_ms": round(1000 * pool[svc], 2) if svc in pool and pool[svc] == pool[svc] else None}
    return {"start": start.isoformat(), "end": end.isoformat(), "services": services,
            "nodes_cpu_cores": {k: round(v, 2) for k, v in sorted(node.items())},
            "platform_cpu_cores": {k: round(v, 3) for k, v in sorted(plat.items())}}


def show(d: dict) -> None:
    print(f"window {d['start']} .. {d['end']}")
    print(f"  {'service':10s} {'req/s':>7s} {'cores':>6s} {'ms CPU/req':>10s} {'busiest pod':>11s} "
          f"{'in flight':>9s} {'loop p99':>8s} {'pool p95':>8s}")
    for svc, s in d["services"].items():
        print(f"  {svc:10s} {s['req_per_s']:7.1f} {s['cpu_cores']:6.3f} {s['cpu_ms_per_req'] or 0:10.2f} "
              f"{s['busiest_pod_cores']:11.3f} {s['inflight']:9.2f} {s['loop_lag_p99_ms'] or 0:8.1f} "
              f"{s['pool_wait_p95_ms'] or 0:8.2f}")
    print("  nodes (cores):", ", ".join(f"{k}={v}" for k, v in d["nodes_cpu_cores"].items()))
    print("  platform (cores):", ", ".join(f"{k}={v}" for k, v in d["platform_cpu_cores"].items()))


if __name__ == "__main__":
    s, e = datetime.fromisoformat(sys.argv[1]), datetime.fromisoformat(sys.argv[2])
    data = window(s, e)
    show(data)
    if "--json" in sys.argv:
        with open(sys.argv[sys.argv.index("--json") + 1], "w") as f:
            json.dump(data, f, indent=1)
