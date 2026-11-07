#!/usr/bin/env bash
# Where did latency change between two load runs? Medians (and p95) per service/route and per
# dependency call, each over a 3-minute window ending at the given UTC time.
#   bash v2/experiments/e2/compare-windows.sh <label-A> <end-A> <label-B> <end-B>
set -euo pipefail
LA=$1; TA=$2; LB=$3; TB=$4
q() { kubectl get --raw "/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query?time=$2&query=$(jq -rn --arg s "$1" '$s|@uri')"; }
row() { # $1 = PromQL template with QQ for the quantile, $2 = jq label expression
  for qq in 0.5 0.95; do
    a=$(q "${1//QQ/$qq}" "$TA" | jq -r ".data.result[] | [$2, .value[1]] | @tsv")
    b=$(q "${1//QQ/$qq}" "$TB" | jq -r ".data.result[] | [$2, .value[1]] | @tsv")
    join -t $'\t' <(sort <<<"$a") <(sort <<<"$b") |
      awk -F'\t' -v q="$qq" '{ if ($2 != "NaN" && $3 != "NaN") printf "  p%-3s %-42s %8.1f ms -> %8.1f ms  (%+7.1f)\n", q*100, $1, $2*1000, $3*1000, ($3-$2)*1000 }'
  done
}
echo "== server side: request duration per service and route ($LA -> $LB)"
row 'histogram_quantile(QQ, sum by (service, route, le) (rate(http_server_request_duration_seconds_bucket{namespace="storefront"}[3m])))' \
    '(.metric.service + " " + .metric.route)'
echo "== client side: one attempt of a call to a dependency"
row 'histogram_quantile(QQ, sum by (service, upstream, le) (rate(upstream_request_duration_seconds_bucket{namespace="storefront"}[3m])))' \
    '(.metric.service + " -> " + .metric.upstream)'
echo "== database: connection-pool wait"
row 'histogram_quantile(QQ, sum by (service, le) (rate(db_pool_acquire_seconds_bucket{namespace="storefront"}[3m])))' \
    '(.metric.service + " pool wait")'
echo "== database: SQL statements as seen by the client (Tempo span metrics)"
row 'histogram_quantile(QQ, sum by (service, span_name, le) (rate(traces_spanmetrics_latency_bucket{span_kind="SPAN_KIND_CLIENT", span_name=~"SELECT|UPDATE|INSERT|BEGIN;|COMMIT;"}[3m])))' \
    '(.metric.service + " " + .metric.span_name)'
