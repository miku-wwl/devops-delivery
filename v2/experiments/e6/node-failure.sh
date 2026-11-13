#!/usr/bin/env bash
# A worker stops answering ([注入]: docker pause freezes the node container - kubelet, containerd and
# every pod on it), under load. Timeline and SLO impact.
#   bash v2/experiments/e6/node-failure.sh <label> <node> [hold-seconds] [rate]
# Every 2 s: the node's Ready condition, how many endpoints of the storefront services on that node
# are still ready, pods of the cluster that are Pending or Terminating. k6 runs at <rate> it/s for
# 60 s before, <hold> s during and 180 s after; its failures are counted per 10 s (client side:
# includes what never reaches the services). The node is unpaused at the end in every case (trap).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; NODE=${2:?node}; HOLD=${3:-420}; RATE=${4:-30}
OUT="$ROOT/v2/evidence/e6/$LABEL"; mkdir -p "$OUT"
CSV=$(mktemp --suffix=.csv)
trap 'docker unpause "$NODE" >/dev/null 2>&1; rm -f "$CSV"; [ -n "${watcher:-}" ] && kill $watcher 2>/dev/null' EXIT
echo "== on $NODE before: $(kubectl get pods -A --field-selector spec.nodeName="$NODE" --no-headers | wc -l) pods"
kubectl get pods -A --field-selector spec.nodeName="$NODE" --no-headers | awk '$1 ~ /^(storefront|data|monitoring|argocd|kyverno|secrets|keda)$/ {print "  " $1 "/" $2}'
echo "== tolerations of a storefront pod: $(kubectl -n storefront get pods -l app.kubernetes.io/name=catalog -o json | jq -c '[.items[0].spec.tolerations[] | select(.key | test("unreachable|not-ready")) | {key, tolerationSeconds}]')"
sample() {
  local r e p t
  r=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  e=$(kubectl -n storefront get endpointslices -o json | jq -r --arg n "$NODE" '[.items[].endpoints[]? | select(.nodeName == $n)] | "\(map(select(.conditions.ready)) | length)/\(length)"')
  p=$(kubectl get pods -A --no-headers 2>/dev/null | awk '$4 == "Pending" {p++} $4 == "Terminating" {t++} END {printf "%d %d", p, t}')
  echo "$(date -u +%T) ready=$r endpoints-on-node-ready=$e pending/terminating=$p"
}
( while true; do sample; sleep 2; done ) > "$OUT/watch.txt" 2>&1 &
watcher=$!
bash "$ROOT/v2/platform/cluster/lb-limits.sh" >/dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
DUR=$((60 + HOLD + 180))
BASE_URL=$GW RATE=$RATE DURATION=${DUR}s SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet --out csv="$CSV" "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1 &
k6pid=$!
sleep 60
T0=$(date -u +%s); echo "$(date -u +%T) docker pause $NODE"; docker pause "$NODE" >/dev/null
sleep "$HOLD"
echo "$(date -u +%T) docker unpause $NODE"; docker unpause "$NODE" >/dev/null
wait $k6pid
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" >/dev/null; grep -E "requests=|browse:|order:" "$OUT/k6.txt" | sed 's/^/  /'
sleep 20; kill $watcher 2>/dev/null; watcher=
echo "== timeline (lines where something changed; t = seconds after the pause)"
awk -v t0="$T0" '{split($1, h, ":"); sig = $2 " " $3 " " $4 " " $5} sig != prev {print; prev = sig}' "$OUT/watch.txt" |
  while read -r line; do ts=${line%% *}; echo "  t=$(( $(date -u -d "$(date -u +%F) $ts" +%s) - T0 ))s $line"; done
echo "== client failures per 10 s (k6 http_req_failed; t = seconds after the pause)"
awk -F, -v t0="$T0" '$1 == "http_req_failed" {b = int(($2 - t0) / 10) * 10; n[b]++; f[b] += $3} END {for (b in n) printf "%d %d %d\n", b, n[b], f[b]}' "$CSV" |
  sort -n | awk '{printf "  t=%5ds  %4d requests  %4d failed  %5.1f %%\n", $1, $2, $3, 100 * $3 / $2}'
echo "== events: evictions by the node controller, and pods that could not be placed"
kubectl get events -A -o json | jq -r --arg t "$(date -u -d @"$T0" +%FT%TZ)" '.items[] | select((.lastTimestamp // .eventTime // "") >= $t) | select(.reason | test("TaintManagerEviction|FailedScheduling|NodeNotReady")) | "  \((.lastTimestamp // .eventTime) | .[11:19]) \(.reason) \(.involvedObject.namespace // "")/\(.involvedObject.name): \(.message | .[0:150])"' | sort | uniq | head -30
echo "== after: pods not Running/Completed, and where the storefront runs"
kubectl get pods -A --no-headers | grep -vE "Running|Completed" | sed 's/^/  /' | head -10
kubectl -n storefront get pods -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName --no-headers | sed 's/^/  /'
