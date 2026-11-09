#!/usr/bin/env bash
# Where does a gateway request wait? Its calls to each upstream in a time window, from Prometheus.
#   bash v2/experiments/e3/gateway-wait.sh <start-iso> <end-iso>
# Per upstream: calls per second by outcome, the gateway's client-side mean duration (includes the
# mesh and the upstream's queue), the upstream's own server-side mean (its middleware), and
# rejected calls per second by reason (breaker, bulkhead, retry budget, deadline).
set -euo pipefail
S=${1:?start}; E=${2:?end}; W=$(( $(date -d "$E" +%s) - $(date -d "$S" +%s) ))s
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
q() { kubectl get --raw "$P/query?time=$(date -d "$E" +%s)&query=$(jq -rn --arg q "$1" '$q|@uri')" |
  jq -r '.data.result[] | "\(.metric | del(.__name__) | to_entries | map(.value) | join(" ")) \(.value[1] | tonumber | . * 100 | round / 100)"'; }
echo "calls/s by upstream and outcome:"; q "sum by (upstream, outcome) (rate(upstream_requests_total{service=\"gateway\"}[$W]))" | sed 's/^/  /'
echo "client-side mean ms by upstream:"; q "1000 * sum by (upstream) (rate(upstream_request_duration_seconds_sum{service=\"gateway\"}[$W])) / sum by (upstream) (rate(upstream_request_duration_seconds_count{service=\"gateway\"}[$W]))" | sed 's/^/  /'
echo "server-side mean ms of the upstreams:"; q "1000 * sum by (service) (rate(http_server_request_duration_seconds_sum{service=~\"catalog|orders\"}[$W])) / sum by (service) (rate(http_server_request_duration_seconds_count{service=~\"catalog|orders\"}[$W]))" | sed 's/^/  /'
echo "rejected/s by upstream and reason:"; q "sum by (upstream, reason) (rate(upstream_rejected_total{service=\"gateway\"}[$W]))" | sed 's/^/  /'
echo "gateway CPU, its node's ztunnel CPU, waypoint CPU (cores):"
node=$(kubectl -n storefront get pods -l app.kubernetes.io/name=gateway -o jsonpath='{.items[0].spec.nodeName}')
q "sum(rate(container_cpu_usage_seconds_total{namespace=\"storefront\",pod=~\"gateway-.*\",container=\"app\"}[$W]))" | sed 's/^/  gateway /'
q "sum(rate(container_cpu_usage_seconds_total{namespace=\"istio-system\",pod=~\"ztunnel-.*\",container!=\"\",node=\"$node\"}[$W]))" | sed "s/^/  ztunnel on $node /"
q "sum(rate(container_cpu_usage_seconds_total{namespace=\"storefront\",pod=~\"waypoint-.*\",container!=\"\"}[$W]))" | sed 's/^/  waypoint /'
