#!/usr/bin/env bash
# How evenly does each service's traffic spread over its replicas?
#   bash v2/experiments/load/distribution.sh [window, default 5m]
# Server-side request counts per pod over the window (Prometheus, through the API server's
# service proxy). With perfect balancing every pod of a service gets 1/N of its requests.
set -euo pipefail
WINDOW=${1:-5m}
q() { kubectl get --raw "/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query?query=$(jq -rn --arg s "$1" '$s|@uri')"; }
q "sum by (service, pod) (increase(http_server_requests_total{namespace=\"storefront\"}[$WINDOW]))" |
  jq -r '.data.result[] | [.metric.service, .metric.pod, (.value[1] | tonumber | round)] | @tsv' |
  sort | awk -F'\t' '
    BEGIN { printf "%-10s %-30s %8s %7s\n", "service", "pod", "requests", "share" > "/dev/stderr" }
    { n[$1]++; pod[$1, n[$1]] = $2; c[$1, n[$1]] = $3; total[$1] += $3 }
    END {
      for (s in total) {
        if (total[s] == 0) continue
        for (i = 1; i <= n[s]; i++)
          printf "%-10s %-30s %8d %6.1f%%\n", s, pod[s, i], c[s, i], 100 * c[s, i] / total[s]
      }
    }' | sort -k1,1 -k2,2
