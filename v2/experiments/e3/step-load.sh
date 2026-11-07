#!/usr/bin/env bash
# Step load (open model): each rate held for STEP seconds, then the next.
#   bash v2/experiments/e3/step-load.sh <label> <rate> [<rate> ...]
# For every step: the k6 summary (achieved rate, latency percentiles, failures, dropped
# iterations) and the resource/queueing statistics of the step window (window_stats.py,
# skipping the first 30 s). k6 runs on CPUs 0-3, outside the worker nodes, at most MAX_VUS VUs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; shift
STEP=${STEP:-120}; MAX_VUS=${MAX_VUS:-600}
OUT="$ROOT/v2/evidence/e3/steps-$LABEL"; mkdir -p "$OUT"
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
for rate in "$@"; do
  start=$(date -u +%FT%TZ)
  BASE_URL=$GW RATE=$rate DURATION=${STEP}s MAX_VUS=$MAX_VUS SUMMARY="$OUT/k6-$rate.json" \
    taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6-$rate.txt" 2>&1
  end=$(date -u +%FT%TZ)
  echo "=== rate $rate it/s  ($start .. $end)"
  cat "$OUT/k6-$rate.txt"
  python3 "$HERE/window_stats.py" "$(date -u -d "$start + 30 seconds" +%FT%T+00:00)" \
    "$(date -u -d "$end" +%FT%T+00:00)" --json "$OUT/window-$rate.json" | tail -n +2
  sleep 10
done
