#!/usr/bin/env bash
# Canary abort drill (E8, chapter 9; hypothesis C3 in evidence/e8/canary-prediction.md).
#   bash v2/experiments/e8/canary-abort.sh <run> [fault-seconds] [after-seconds]
# 1. the preview header still reaches only the canary (C2, under live weights);
# 2. the canary turns faulty: 50 % of its answers are 503 (/admin/faults on both canary pods);
# 3. probe.py sends a request every 25 ms through the layer-7 entrance during the whole drill;
# 4. after <fault-seconds> the decision: a merge request sets the canary's weight to 0 (rollback),
#    through the gate; merged as soon as its pipeline succeeds;
# 5. probing goes on for <after-seconds>; the faults are removed in every case (trap).
# Evidence: evidence/e8/<run>/ (run.txt, probe.log).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RUN=${1:?run}; FAULT=${2:-90}; AFTER=${3:-150}
OUT="$ROOT/v2/evidence/e8/$RUN"; mkdir -p "$OUT"
exec > >(tee "$OUT/run.txt") 2>&1
now() { date -u +%T.%3N; }
faults() {
  for p in $(kubectl -n storefront get pods -l app.kubernetes.io/name=gateway-canary -o jsonpath='{.items[*].metadata.name}'); do
    printf '%s' "$1" | kubectl -n storefront exec -i "$p" -c app -- python -c "import sys, urllib.request; r = urllib.request.Request('http://127.0.0.1:8080/admin/faults', data=sys.stdin.buffer.read(), method='PUT', headers={'Content-Type': 'application/json'}); print('  $p', urllib.request.urlopen(r, timeout=5).read().decode())"
  done
}
trap 'faults "{}" >/dev/null 2>&1; [ -n "${probe:-}" ] && kill $probe 2>/dev/null' EXIT
IP=$(kubectl -n storefront get gateway storefront-ingress -o jsonpath='{.status.addresses[0].value}')
URL=http://$IP:8080
echo "== $(now) route weights: $(kubectl -n storefront get httproute storefront -o jsonpath='{.spec.rules[1].backendRefs[*].weight}')"
echo "== $(now) C2 under live weights: 10 s of requests with x-storefront-preview: canary"
timeout 30 python3 "$HERE/probe.py" "$URL" 10 0.025 x-storefront-preview:canary | awk '{n[$3 " " $2]++} END {for (k in n) print "  version " k ": " n[k]}'
echo "== $(now) the canary turns faulty (50 % 503)"
faults '{"error_rate": 0.5, "status": 503}'
python3 "$HERE/probe.py" "$URL" $((FAULT + AFTER + 120)) 0.025 > "$OUT/probe.log" &
probe=$!
sleep "$FAULT"
T_DECIDE=$(date +%s.%N); echo "== $(now) decision: roll the canary back (weight 0)"
sed -i 's/        - {name: gateway, port: 8080, weight: 95}/        - {name: gateway, port: 8080, weight: 100}/; s/        - {name: gateway-canary, port: 8080, weight: 5}/        - {name: gateway-canary, port: 8080, weight: 0}/' \
  "$ROOT/v2/gitops/platform/manifests/routes/storefront.yaml"   # since R3 (was mesh/ingress-storefront.yaml)
bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" fd38028 "e8: canary rollback - weight 0" | sed 's/^/  /'
T_MERGED=$(date +%s.%N); echo "== $(now) merged"
kubectl -n argocd annotate app mesh argocd.argoproj.io/refresh=normal --overwrite >/dev/null
for i in $(seq 1 60); do
  w=$(kubectl -n storefront get httproute storefront -o jsonpath='{.spec.rules[1].backendRefs[1].weight}')
  [ "$w" = 0 ] && { echo "== $(now) the route in the cluster has weight 0"; break; }
  sleep 1
done
T_APPLIED=$(date +%s.%N)
sleep "$AFTER"
kill $probe 2>/dev/null; wait $probe 2>/dev/null; probe=   # not a bare wait: it would also wait for the tee of exec
faults '{}'
python3 "$HERE/abort_report.py" "$OUT/probe.log" "$T_DECIDE" "$T_MERGED" "$T_APPLIED" | tee "$OUT/report.txt"
