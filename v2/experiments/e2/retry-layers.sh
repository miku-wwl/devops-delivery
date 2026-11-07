#!/usr/bin/env bash
# How many times does payments get called per customer order when it fails? ([注入] fault)
#   bash v2/experiments/e2/retry-layers.sh <label> <status>     # status: 500 or 503
# Payments answers every /charges with <status> (fault injection on both pods). 60 orders are
# placed at 2 per second. Exact counters are read from every pod's /metrics before and after
# (Prometheus would blur them with its 15 s scrape), and the attempts per layer are reported:
#   gateway -> orders (app retries, idempotent), orders -> payments (app retries with budget),
#   and whatever the mesh adds in between (waypoint retries) shows up as extra server-side calls.
set -euo pipefail
LABEL=${1:?label}; STATUS=${2:?status}
NS=storefront
GW=http://$(kubectl -n $NS get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
pods() { kubectl -n $NS get pods -l app.kubernetes.io/name="$1" -o jsonpath='{.items[*].metadata.name}'; }
metric_sum() { # service, python filter on (name, labels) -> sum over pods
  local svc=$1 filter=$2 total=0 v
  for p in $(pods "$svc"); do
    v=$(kubectl -n $NS exec "$p" -c app -- python -c "
import urllib.request, re
total = 0.0
for line in urllib.request.urlopen('http://localhost:8080/metrics').read().decode().splitlines():
    if line.startswith('#'): continue
    m = re.match(r'([a-z_]+)(\{[^}]*\})? ([0-9.e+-]+)', line)
    if not m: continue
    name, labels, value = m.group(1), m.group(2) or '', float(m.group(3))
    if $filter: total += value
print(int(total))")
    total=$((total + v))
  done
  echo "$total"
}
faults() { for p in $(pods payments); do
  kubectl -n $NS exec "$p" -c app -- python -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:8080/admin/faults', method='PUT',
      data=json.dumps($1).encode(), headers={'Content-Type': 'application/json'})
print(urllib.request.urlopen(req).read().decode())" >/dev/null; done; }
snap() {
  echo "$(metric_sum gateway "name == 'http_server_requests_total' and 'route=\"/api/orders\"' in labels") \
$(metric_sum orders "name == 'http_server_requests_total' and 'route=\"/orders\"' in labels and 'POST' in labels") \
$(metric_sum orders "name == 'upstream_requests_total' and 'upstream=\"payments\"' in labels") \
$(metric_sum payments "name == 'http_server_requests_total' and 'route=\"/charges\"' in labels")"
}
read -r g0 o0 op0 p0 < <(snap)
faults "{\"error_rate\": 1.0, \"status\": $STATUS}"
cat > /tmp/orders-only.js <<'EOF'
import http from 'k6/http';
export const options = { scenarios: { o: { executor: 'constant-arrival-rate', rate: 2, timeUnit: '1s',
  duration: '30s', preAllocatedVUs: 20, maxVUs: 50 } } };
export default function () {
  http.post(`${__ENV.BASE_URL}/api/orders`, JSON.stringify({ customer_id: 'c-retry', items: [{ product_id: 'sku-010', qty: 1 }] }),
    { headers: { 'Content-Type': 'application/json', 'Idempotency-Key': `retry-${__VU}-${__ITER}-${Date.now()}` } });
}
EOF
BASE_URL=$GW taskset -c 0-3 k6 run --quiet /tmp/orders-only.js >/dev/null 2>&1 || true
faults '{"error_rate": 0}'
sleep 2
read -r g1 o1 op1 p1 < <(snap)
dg=$((g1 - g0)); do_=$((o1 - o0)); dop=$((op1 - op0)); dp=$((p1 - p0))
echo "scenario=$LABEL payments answers $STATUS"
echo "  customer orders (gateway POST /api/orders):   $dg"
echo "  orders POST /orders received:                 $do_   ($(awk -v a=$do_ -v b=$dg 'BEGIN{printf "%.2f", a/b}') per customer order)"
echo "  orders -> payments attempts (app side):       $dop   ($(awk -v a=$dop -v b=$dg 'BEGIN{printf "%.2f", a/b}') per customer order)"
echo "  payments POST /charges received (server):     $dp   ($(awk -v a=$dp -v b=$dg 'BEGIN{printf "%.2f", a/b}') per customer order)"
echo "  extra calls added between orders and payments: $((dp - dop))"
