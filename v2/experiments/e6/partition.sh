#!/usr/bin/env bash
# A network partition between one zone and the other two ([注入]), under load.
#   bash v2/experiments/e6/partition.sh <label> <node> [hold-seconds] [rate]
# Inside the node container of <node> (its network namespace carries the node's and its pods'
# traffic), a chain E6PART drops everything from and to the other workers' node addresses and pod
# networks. The control plane and the load balancer stay reachable: the node keeps reporting Ready.
# Every 2 s: the node's Ready condition, ready endpoints of storefront services on the node,
# Prometheus targets that are down. k6 runs 60 s before, <hold> s during and 180 s after; failures
# per 10 s. The chain is removed at the end in every case (trap).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; NODE=${2:?node}; HOLD=${3:-300}; RATE=${4:-30}
OUT="$ROOT/v2/evidence/e6/$LABEL"; mkdir -p "$OUT"
CSV=$(mktemp --suffix=.csv)
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
unpartition() {
  docker exec "$NODE" sh -c 'for c in FORWARD INPUT OUTPUT; do while iptables -D $c -j E6PART 2>/dev/null; do :; done; done; iptables -F E6PART 2>/dev/null; iptables -X E6PART 2>/dev/null' || true
}
trap 'unpartition; rm -f "$CSV"; [ -n "${watcher:-}" ] && kill $watcher 2>/dev/null' EXIT
others=$(kubectl get nodes -o json | jq -r --arg n "$NODE" '.items[] | select(.metadata.name != $n and (.metadata.name | test("worker"))) | "\(.status.addresses[] | select(.type == "InternalIP") | .address) \(.spec.podCIDR)"' | tr '\n' ' ')
echo "== $NODE ($(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')) will be cut off from: $others"
echo "== storefront pods on $NODE: $(kubectl -n storefront get pods --field-selector spec.nodeName="$NODE" -o jsonpath='{.items[*].metadata.name}')"
sample() {
  local r e d
  r=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  e=$(kubectl -n storefront get endpointslices -o json | jq -r --arg n "$NODE" '[.items[].endpoints[]? | select(.nodeName == $n)] | "\(map(select(.conditions.ready)) | length)/\(length)"')
  d=$(kubectl get --raw "$P/query?query=$(jq -rn --arg q 'count(up == 0) or vector(0)' '$q|@uri')" 2>/dev/null | jq -r '.data.result[0].value[1] // "?"')
  echo "$(date -u +%T) ready=$r endpoints-on-node-ready=$e targets-down=$d"
}
( while true; do sample; sleep 2; done ) > "$OUT/watch.txt" 2>&1 &
watcher=$!
bash "$ROOT/v2/platform/cluster/lb-limits.sh" >/dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
BASE_URL=$GW RATE=$RATE DURATION=$((60 + HOLD + 180))s SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet --out csv="$CSV" "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1 &
k6pid=$!
sleep 60
T0=$(date -u +%s); echo "$(date -u +%T) partition on"
docker exec -i "$NODE" sh -s $others <<'SH'
iptables -N E6PART
while [ $# -gt 0 ]; do
  for a in "$1" "$2"; do iptables -A E6PART -s "$a" -j DROP; iptables -A E6PART -d "$a" -j DROP; done
  shift 2
done
for c in FORWARD INPUT OUTPUT; do iptables -I $c 1 -j E6PART; done
iptables -S E6PART | sed 's/^/  /'
SH
sleep "$HOLD"
echo "$(date -u +%T) partition off"; unpartition
wait $k6pid
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" >/dev/null; grep -E "requests=|browse:|order:" "$OUT/k6.txt" | sed 's/^/  /'
sleep 20; kill $watcher 2>/dev/null; watcher=
echo "== timeline (lines where something changed; t = seconds after the partition started)"
awk '{sig = $2 " " $3 " " $4} sig != prev {print; prev = sig}' "$OUT/watch.txt" |
  while read -r line; do ts=${line%% *}; echo "  t=$(( $(date -u -d "$(date -u +%F) $ts" +%s) - T0 ))s $line"; done
echo "== client failures per 10 s (k6 http_req_failed)"
awk -F, -v t0="$T0" '$1 == "http_req_failed" {b = int(($2 - t0) / 10) * 10; n[b]++; f[b] += $3} END {for (b in n) printf "%d %d %d\n", b, n[b], f[b]}' "$CSV" |
  sort -n | awk '{printf "  t=%5ds  %4d requests  %4d failed  %5.1f %%\n", $1, $2, $3, 100 * $3 / $2}'
echo "== during the partition (last $((HOLD - 30)) s of it): 5xx and calls between services by outcome"
end=$((T0 + HOLD)); w=$((HOLD - 30))s
kubectl get --raw "$P/query?time=$end&query=$(jq -rn --arg q "sum by (service, code) (rate(http_server_requests_total{namespace=\"storefront\",code=~\"5..\"}[$w]))" '$q|@uri')" | jq -r '.data.result[] | "  5xx \(.metric.service) \(.metric.code) \(.value[1] | tonumber | . * 1000 | round / 1000)/s"'
kubectl get --raw "$P/query?time=$end&query=$(jq -rn --arg q "sum by (service, upstream, outcome) (rate(upstream_requests_total{namespace=\"storefront\",outcome!=\"ok\"}[$w])) > 0" '$q|@uri')" | jq -r '.data.result[] | "  call \(.metric.service) -> \(.metric.upstream) \(.metric.outcome) \(.value[1] | tonumber | . * 1000 | round / 1000)/s"'
echo "== after: pods not Running/Completed: $(kubectl get pods -A --no-headers | grep -vcE 'Running|Completed')"
