#!/usr/bin/env bash
# One row per pod of the services in a time window, from Prometheus (also for past windows).
#   bash v2/experiments/e4/pod-table.sh <services-regex> <start-iso> <end-iso>
# Columns: node, CPU limit, requests/s, CPU cores, CPU ms per request, latency p50 and p99 (all
# routes), event-loop lag p99, and the share of CFS periods in which the pod was throttled
# (cAdvisor; "-" when the pod has no CPU limit, the kernel then never throttles it).
set -euo pipefail
SVC=${1:?services regex}; S=${2:?start}; E=${3:?end}
T=$(date -d "$E" +%s); W=$(( T - $(date -d "$S" +%s) ))s
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
q() { kubectl get --raw "$P/query?time=$T&query=$(jq -rn --arg q "$1" '$q|@uri')" |
  jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"'; }
sel="namespace=\"storefront\",pod=~\"($SVC)-.*\""
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
{
  q "sum by (pod)(rate(http_server_requests_total{$sel}[$W]))" | sed 's/^/rps /'
  q "sum by (pod)(rate(container_cpu_usage_seconds_total{$sel,container=\"app\"}[$W]))" | sed 's/^/cpu /'
  q "histogram_quantile(0.5, sum by (pod, le)(rate(http_server_request_duration_seconds_bucket{$sel}[$W])))" | sed 's/^/p50 /'
  q "histogram_quantile(0.99, sum by (pod, le)(rate(http_server_request_duration_seconds_bucket{$sel}[$W])))" | sed 's/^/p99 /'
  q "histogram_quantile(0.99, sum by (pod, le)(rate(event_loop_lag_seconds_bucket{$sel}[$W])))" | sed 's/^/lag /'
  q "sum by (pod)(rate(container_cpu_cfs_throttled_periods_total{$sel,container=\"app\"}[$W])) / sum by (pod)(rate(container_cpu_cfs_periods_total{$sel,container=\"app\"}[$W]))" | sed 's/^/thr /'
} > "$tmp"
echo "window $S .. $E"
printf "%-34s %-12s %-6s %7s %6s %10s %8s %8s %9s %10s\n" pod node limit req/s cores "ms CPU/req" "p50 ms" "p99 ms" "lag p99" throttled
# node and CPU limit from kube-state-metrics, so that pods deleted since the window still show up
{ kubectl get --raw "$P/query?time=$T&query=$(jq -rn --arg q "max by (pod, node) (kube_pod_info{$sel})" '$q|@uri')" |
    jq -r '.data.result[] | "node \(.metric.pod) \(.metric.node)"'
  kubectl get --raw "$P/query?time=$T&query=$(jq -rn --arg q "max by (pod) (kube_pod_container_resource_limits{$sel,resource=\"cpu\"})" '$q|@uri')" |
    jq -r '.data.result[] | "lim \(.metric.pod) \(.value[1])"'; } |
  awk 'NR == FNR {if ($1 == "node") node[$2] = $3; else lim[$2] = ($3 * 1000) "m"; next}
       {v[$2, $1] = $3; pods[$2] = 1}
       END {for (p in pods) printf "%-34s %-12s %-6s %7.1f %6.3f %10.2f %8.1f %8.1f %9.1f %10s\n", p, node[p], (p in lim ? lim[p] : "none"),
            v[p, "rps"], v[p, "cpu"], (v[p, "rps"] > 0 ? 1000 * v[p, "cpu"] / v[p, "rps"] : 0), 1000 * v[p, "p50"],
            1000 * v[p, "p99"], 1000 * v[p, "lag"], ((p, "thr") in v ? sprintf("%.0f %%", 100 * v[p, "thr"]) : "-")}' - "$tmp" | sort
