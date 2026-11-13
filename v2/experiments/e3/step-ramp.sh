#!/usr/bin/env bash
# Step load in ONE k6 run: a warm-up ramp, then every rate held STEP s, RAMP s between steps.
#   bash v2/experiments/e3/step-ramp.sh <label> <rate>[,<rate> ...]
# Unlike step-load.sh (one k6 process per step - the first run of chapter 4), connections and
# pools stay warm from one step to the next, so a step does not begin with a cold start. For every
# step: k6's view (achieved rate, failures, latency - the requests are tagged with their stage)
# and window_stats.py over the step without its first 30 s.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; RATES=${2:?rates, comma-separated}
STEP=${STEP:-120}; RAMP=${RAMP:-10}; WARMUP=${WARMUP:-30}; MAX_VUS=${MAX_VUS:-600}
OUT="$ROOT/v2/evidence/e3/steps-$LABEL"; mkdir -p "$OUT"
bash "$ROOT/v2/platform/cluster/lb-limits.sh" > /dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
t0=$(date -u +%s)
BASE_URL=$GW STAGES=$RATES STEP=$STEP RAMP=$RAMP WARMUP=$WARMUP MAX_VUS=$MAX_VUS SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" > /dev/null
cat "$OUT/k6.txt"
sleep 20   # the last scrape must cover the end of the last step
# step windows from the start time (k6 needs about a second to start; the first 30 s of every
# step are skipped anyway)
s=$((t0 + WARMUP)); first=1
for rate in ${RATES//,/ }; do
  [ -n "$first" ] || s=$((s + RAMP)); first=
  e=$((s + STEP))
  echo "=== step $rate it/s ($(date -u -d @$s +%T) .. $(date -u -d @$e +%T))"
  python3 "$HERE/window_stats.py" "$(date -u -d @$((s + 30)) +%FT%T+00:00)" "$(date -u -d @$e +%FT%T+00:00)" \
    --json "$OUT/window-$rate.json" | tail -n +2
  s=$e
done
