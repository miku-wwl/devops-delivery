#!/usr/bin/env bash
# One fault-injection phase under load ([注入]): steady state, fault, recovery - one k6 run.
#   bash v2/experiments/e6/fault-phase.sh <label> <service> '<faults-json>' [rate] [secs-per-part]
# Example: bash v2/experiments/e6/fault-phase.sh slow-naive inventory '{"latency_ms": 1500}' 30 120
# The fault is set on every pod of <service> through its /admin/faults endpoint (in the pod,
# localhost) after <secs> of steady state and removed after another <secs>; k6 runs <secs> more
# (recovery). Prints, per part (steady / fault / recovery): the k6 stage results and, from
# Prometheus, per-service request rate and 5xx, latency p95, calls between services by outcome,
# retries, fast rejections and the call amplification at the faulted service.
# The resilience mode of the services is whatever Git says (common.yaml: resilienceMode).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; SVC=${2:?service}; FAULT=${3:?faults json}; RATE=${4:-30}; SECS=${5:-120}
OUT="$ROOT/v2/evidence/e6/$LABEL"; mkdir -p "$OUT"
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
faults() {   # json: set on every pod of $SVC
  for p in $(kubectl -n storefront get pods -l app.kubernetes.io/name="$SVC" -o jsonpath='{.items[*].metadata.name}'); do
    printf '%s' "$1" | kubectl -n storefront exec -i "$p" -c app -- python -c "import sys, urllib.request; r = urllib.request.Request('http://127.0.0.1:8080/admin/faults', data=sys.stdin.buffer.read(), method='PUT', headers={'Content-Type': 'application/json'}); print('  $p', urllib.request.urlopen(r, timeout=5).read().decode())"
  done
}
trap 'faults "{}" >/dev/null 2>&1' EXIT
q() { kubectl get --raw "$P/query?time=$2&query=$(jq -rn --arg q "$1" '$q|@uri')" | jq -r '.data.result[] | "\(.metric | del(.__name__) | to_entries | map("\(.key)=\(.value)") | join(",")) \(.value[1] | tonumber | . * 1000 | round / 1000)"' | sort; }
echo "== mode: $(kubectl -n storefront get deploy orders -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RESILIENCE_MODE")].value}'); fault on $SVC: $FAULT; $RATE it/s; $SECS s steady, $SECS s fault, $SECS s recovery"
bash "$ROOT/v2/platform/cluster/lb-limits.sh" >/dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
# k6 stages 1-<rate>, 2-<rate>, 3-<rate> = steady, fault, recovery (5 s warm-up, 1 s between stages)
BASE_URL=$GW STAGES="$RATE,$RATE,$RATE" STEPS="$SECS,$SECS,$SECS" WARMUP=5 RAMP=1 SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1 &
k6pid=$!
sleep 5; t0=$(date -u +%s)
sleep "$SECS"; echo "$(date -u +%T) fault on"; faults "$FAULT"
sleep $((SECS + 1)); echo "$(date -u +%T) fault off"; faults "{}" >/dev/null
wait $k6pid
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" >/dev/null; grep -E "^stage|requests=" "$OUT/k6.txt" | sed 's/^/  /'
sleep 20
for i in 0 1 2; do
  part=$(echo steady fault recovery | cut -d' ' -f$((i + 1))); end=$((t0 + (i + 1) * SECS + i)); w=$((SECS - 20))s
  echo "=== $part (window ending $(date -u -d @$end +%T), last $w)"
  echo "-- requests/s and 5xx/s per service"
  q "sum by (service) (rate(http_server_requests_total{namespace=\"storefront\"}[$w]))" $end | sed 's/^/  req /'
  q "sum by (service) (rate(http_server_requests_total{namespace=\"storefront\",code=~\"5..\"}[$w]))" $end | sed 's/^/  5xx /'
  echo "-- latency p95 per service (s)"
  q "histogram_quantile(0.95, sum by (service, le) (rate(http_server_request_duration_seconds_bucket{namespace=\"storefront\"}[$w])))" $end | sed 's/^/  p95 /'
  echo "-- calls between services per second, by outcome; retries; fast rejections"
  q "sum by (service, upstream, outcome) (rate(upstream_requests_total{namespace=\"storefront\"}[$w]))" $end | sed 's/^/  call /'
  q "sum by (service, upstream) (rate(upstream_retries_total{namespace=\"storefront\"}[$w]))" $end | sed 's/^/  retry /'
  q "sum by (service, upstream, reason) (rate(upstream_rejected_total{namespace=\"storefront\"}[$w]))" $end | sed 's/^/  reject /'
  echo "-- amplification: calls arriving at $SVC per order placed at the gateway"
  q "sum(rate(http_server_requests_total{namespace=\"storefront\",service=\"$SVC\"}[$w])) / sum(rate(http_server_requests_total{namespace=\"storefront\",service=\"gateway\",route=~\".*orders.*\",method=\"POST\"}[$w]))" $end | sed 's/^/  ratio /'
done
