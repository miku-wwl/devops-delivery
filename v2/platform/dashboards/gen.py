"""Generate Grafana dashboards as ConfigMaps for the Grafana sidecar (label grafana_dashboard=1).

    python v2/platform/dashboards/gen.py      # writes v2/gitops/platform/manifests/dashboards/*.yaml

Dashboards are code: reviewed in merge requests, reproducible, and never edited by hand in Grafana.
"""

from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "gitops" / "platform" / "manifests" / "dashboards"
NS = 'namespace=~"storefront.*"'


def panel(title: str, exprs: list[tuple[str, str]], unit: str, x: int, y: int, w: int = 12, h: int = 8,
          kind: str = "timeseries", desc: str = "") -> dict:
    return {
        "type": kind, "title": title, "description": desc,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {"defaults": {"unit": unit}, "overrides": []},
        "options": {"legend": {"displayMode": "table", "placement": "right", "calcs": ["lastNotNull", "max"]}},
        "targets": [{"refId": chr(65 + i), "expr": e, "legendFormat": legend}
                    for i, (e, legend) in enumerate(exprs)],
    }


def storefront() -> dict:
    p = []
    y = 0
    p.append(panel("Requests per second by service",
                   [(f"sum by (service) (rate(http_server_requests_total{{{NS}}}[1m]))", "{{service}}")],
                   "reqps", 0, y))
    # "or ... * 0": a service without any 5xx has no 5xx series at all; without the fallback
    # the panel shows "No data" instead of 0 (an absent series is not a zero)
    total = f"sum by (service) (rate(http_server_requests_total{{{NS}}}[1m]))"
    p.append(panel("5xx ratio by service",
                   [(f'(sum by (service) (rate(http_server_requests_total{{{NS},code=~"5.."}}[1m])) '
                     f"or {total} * 0) / {total}", "{{service}}")],
                   "percentunit", 12, y))
    y += 8
    p.append(panel("p95 latency by service",
                   [(f"histogram_quantile(0.95, sum by (service, le) "
                     f"(rate(http_server_request_duration_seconds_bucket{{{NS}}}[1m])))", "{{service}}")],
                   "s", 0, y))
    p.append(panel("Calls to dependencies by outcome",
                   [(f"sum by (service, upstream, outcome) (rate(upstream_requests_total{{{NS}}}[1m]))",
                     "{{service}} -> {{upstream}} {{outcome}}")], "reqps", 12, y))
    y += 8
    p.append(panel("Retries and rejected calls",
                   [(f"sum by (service, upstream) (rate(upstream_retries_total{{{NS}}}[1m]))",
                     "retry {{service}} -> {{upstream}}"),
                    (f"sum by (service, upstream, reason) (rate(upstream_rejected_total{{{NS}}}[1m]))",
                     "rejected {{service}} -> {{upstream}} {{reason}}")], "reqps", 0, y,
                   desc="Rejected: breaker open, bulkhead full, retry budget or deadline exhausted"))
    p.append(panel("Circuit breakers (0 closed, 1 half-open, 2 open)",
                   [(f"max by (service, upstream) (circuit_breaker_state{{{NS}}})",
                     "{{service}} -> {{upstream}}")], "none", 12, y))
    y += 8
    p.append(panel("Database pool: connections in use and acquire p95",
                   [(f'sum by (service) (db_pool_connections{{{NS},state="in_use"}})', "in use {{service}}"),
                    (f"histogram_quantile(0.95, sum by (service, le) "
                     f"(rate(db_pool_acquire_seconds_bucket{{{NS}}}[1m]))) * 1000", "acquire p95 ms {{service}}")],
                   "none", 0, y))
    p.append(panel("Orders by result",
                   [(f"sum by (status) (rate(orders_total{{{NS}}}[1m]))", "{{status}}")], "reqps", 12, y))
    y += 8
    p.append(panel("Asynchronous path: outbox and notifications",
                   [(f"max(outbox_pending{{{NS}}})", "outbox pending"),
                    (f"histogram_quantile(0.95, sum by (le) (rate(outbox_delay_seconds_bucket{{{NS}}}[1m])))",
                     "outbox delay p95 (s)"),
                    (f"histogram_quantile(0.95, sum by (le) "
                     f"(rate(notifier_end_to_end_seconds_bucket{{{NS}}}[1m])))", "order -> notification p95 (s)")],
                   "none", 0, y))
    p.append(panel("Pod CPU (cores) and memory (MiB)",
                   [(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{{NS},container="app"}}[1m]))',
                     "cpu {{pod}}"),
                    (f'sum by (pod) (container_memory_working_set_bytes{{{NS},container="app"}}) / 1048576',
                     "mem {{pod}}")], "none", 12, y))
    return {"uid": "storefront-red", "title": "Storefront: services (RED) and dependencies",
            "tags": ["storefront", "v2"], "timezone": "utc", "schemaVersion": 39, "refresh": "10s",
            "time": {"from": "now-30m", "to": "now"}, "panels": p}


def traces() -> dict:
    """One trace by id (variable trace_id) and the service graph from Tempo's metrics generator.
    A dashboard rather than Explore: read-only viewers can open dashboards, not Explore."""
    tempo = {"type": "tempo", "uid": "tempo"}
    return {
        "uid": "storefront-traces", "title": "Storefront: trace and service graph",
        "tags": ["storefront", "v2"], "timezone": "utc", "schemaVersion": 39,
        "time": {"from": "now-1h", "to": "now"},
        "templating": {"list": [{"name": "trace_id", "type": "textbox", "label": "Trace ID", "query": ""}]},
        "panels": [
            {"type": "nodeGraph", "title": "Service graph (Tempo metrics generator)",
             "gridPos": {"x": 0, "y": 0, "w": 24, "h": 16}, "datasource": tempo,
             "targets": [{"refId": "A", "datasource": tempo, "queryType": "serviceMap"}]},
            {"type": "traces", "title": "Trace ${trace_id}",
             "gridPos": {"x": 0, "y": 16, "w": 24, "h": 22}, "datasource": tempo,
             "targets": [{"refId": "A", "datasource": tempo, "queryType": "traceql", "query": "${trace_id}"}]},
        ],
    }


def balance() -> dict:
    """Requests per second per pod for the services with two replicas: shows L4 imbalance and the
    effect of the waypoint (chapter 3)."""
    p = []
    for i, svc in enumerate(("orders", "inventory", "payments")):
        p.append(panel(f"{svc}: requests per second per pod",
                       [(f'sum by (pod) (rate(http_server_requests_total{{{NS},service="{svc}"}}[1m]))', "{{pod}}")],
                       "reqps", 0, i * 8, w=24, h=8))
    return {"uid": "storefront-balance", "title": "Storefront: load per replica",
            "tags": ["storefront", "v2"], "timezone": "utc", "schemaVersion": 39,
            "time": {"from": "now-1h", "to": "now"}, "panels": p}


def capacity() -> dict:
    """Load against saturation (chapter 4): pod CPU next to the one-core ceiling of a Python
    process, latency, event-loop lag, errors, and the time-averaged number of requests in flight
    (rate of the duration sum = X * R, Little's law - a scraped in-flight gauge is not an average)."""
    p = []
    p.append(panel("Load: gateway requests per second", [
        (f'sum(rate(http_server_requests_total{{{NS},service="gateway"}}[1m]))', "gateway req/s")],
        "reqps", 0, 0, w=24, h=6))
    cpu = panel("CPU per pod (cores) - one Python process saturates near 1 core", [
        (f'sum by (pod) (rate(container_cpu_usage_seconds_total{{{NS},container="app",'
         f'pod=~"(gateway|catalog|orders)-.*"}}[1m]))', "{{pod}}")], "none", 0, 6, w=12, h=9)
    cpu["fieldConfig"]["defaults"]["custom"] = {"thresholdsStyle": {"mode": "line"}}
    cpu["fieldConfig"]["defaults"]["thresholds"] = {
        "mode": "absolute", "steps": [{"color": "transparent", "value": None}, {"color": "red", "value": 1}]}
    cpu["fieldConfig"]["defaults"]["max"] = 1.1
    p.append(cpu)
    p.append(panel("p95 latency by service", [
        (f"histogram_quantile(0.95, sum by (service, le) "
         f"(rate(http_server_request_duration_seconds_bucket{{{NS}}}[1m])))", "{{service}}")],
        "s", 12, 6, h=9))
    p.append(panel("Event-loop lag p99 by service", [
        (f"histogram_quantile(0.99, sum by (service, le) (rate(event_loop_lag_seconds_bucket{{{NS}}}[1m])))",
         "{{service}}")], "s", 0, 15, h=8))
    p.append(panel("Requests in flight, time-averaged (rate of the duration sum = X * R)", [
        (f"sum by (service) (rate(http_server_request_duration_seconds_sum{{{NS}}}[1m]))", "{{service}}")],
        "none", 12, 15, h=8))
    p.append(panel("5xx per second by service", [
        (f'sum by (service) (rate(http_server_requests_total{{{NS},code=~"5.."}}[1m]))', "{{service}}")],
        "reqps", 0, 23, h=8))
    p.append(panel("Worker nodes: CPU of all containers (cores, 4 per node)", [
        ('sum by (node) (rate(container_cpu_usage_seconds_total{container!="",pod!="",'
         'node=~"ent-worker.*"}[1m]))', "{{node}}")], "none", 12, 23, h=8))
    return {"uid": "storefront-capacity", "title": "Storefront: load and saturation",
            "tags": ["storefront", "v2"], "timezone": "utc", "schemaVersion": 39,
            "time": {"from": "now-1h", "to": "now"}, "panels": p}


def configmap(name: str, dashboard: dict) -> str:
    body = json.dumps(dashboard, indent=1)
    indented = "\n".join("    " + line for line in body.splitlines())
    return (f"# generated by v2/platform/dashboards/gen.py - do not edit by hand\n"
            f"apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: dashboard-{name}\n  namespace: monitoring\n"
            f"  labels:\n    grafana_dashboard: \"1\"\ndata:\n  {name}.json: |\n{indented}\n")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in (("storefront", storefront), ("storefront-traces", traces), ("storefront-balance", balance),
                        ("storefront-capacity", capacity)):
        (OUT / f"{name}.yaml").write_text(configmap(name, build()), encoding="utf-8", newline="\n")
        print(f"wrote {OUT / f'{name}.yaml'}")
