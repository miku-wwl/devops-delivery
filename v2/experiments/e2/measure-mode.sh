#!/usr/bin/env bash
# One E2 measurement, identical for every mesh mode (none, ambient L4, ambient + waypoint).
#   bash v2/experiments/e2/measure-mode.sh <label> [target-url]
# 3 minutes of the standard k6 mix at 20 iterations/s; a connection census at t=120 s; then
# per-replica request shares over the run, and CPU/memory of the storefront and mesh pods.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}
OUT="$ROOT/v2/evidence/e2"
mkdir -p "$OUT"
GW=${2:-http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080}
echo "mode=$LABEL target=$GW start=$(date -u +%FT%TZ)"
BASE_URL=$GW RATE=20 DURATION=3m SUMMARY="$OUT/k6-$LABEL.json" taskset -c 0-3 \
  k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6-$LABEL.txt" 2>&1 &
K6=$!
sleep 120
echo "--- connections at t=120s"
bash "$ROOT/v2/experiments/load/connections.sh" | grep -v prometheus
wait $K6
echo "--- k6"
cat "$OUT/k6-$LABEL.txt"
sleep 20   # let the last scrape land
echo "--- request share per replica over the run"
bash "$ROOT/v2/experiments/load/distribution.sh" 3m 2>&1
echo "--- resources"
kubectl top pods -n storefront --no-headers | sort
kubectl top pods -n istio-system --no-headers 2>/dev/null | sort
echo "end=$(date -u +%FT%TZ)"
