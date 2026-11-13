#!/usr/bin/env bash
# Reproduce what happened above ~170 iterations/s in the first step load, with live captures:
#   bash v2/experiments/e3/lb-storm.sh <label> [rate] [seconds]
# The LoadBalancer of the gateway Service is emulated by cloud-provider-kind: one Envoy container
# (kindccm-*) on the Docker network, a TCP proxy to the NodePorts. This script records, while k6
# runs the normal storefront mix: Envoy's open-file limit, its crashes and restarts, readiness of
# every storefront pod every 2 s, and the logs of the ztunnel on every worker node (the per-node
# proxy of the ambient mesh, which carries all pod traffic of its node). Nothing is changed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; RATE=${2:-180}; SECS=${3:-60}
OUT="$ROOT/v2/evidence/e3/$LABEL"; mkdir -p "$OUT"
RAW=$(mktemp -d)   # full ztunnel logs are large: only summaries and error lines are kept
LB=$(docker ps --format '{{.Names}}' | grep -E '^kindccm-' | head -1)
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
echo "load balancer container: $LB ($GW)"
docker exec "$LB" sh -c 'p=$(pgrep -x envoy | head -1); echo "envoy pid $p, open files now: $(ls /proc/$p/fd | wc -l)"; grep "open files" /proc/$p/limits'
crashes_before=$(docker logs "$LB" 2>&1 | grep -c 'Caught Segmentation fault')
start=$(date -u +%FT%TZ)
pids=()
for n in ent-worker ent-worker2 ent-worker3; do
  zt=$(kubectl -n istio-system get pods -l app=ztunnel --field-selector spec.nodeName=$n -o name)
  kubectl -n istio-system logs -f "$zt" --since=1s > "$RAW/ztunnel-$n.log" 2>&1 & pids+=($!)
done
( while true; do
    echo "$(date -u +%T) $(kubectl -n storefront get pods --no-headers \
      -o custom-columns=N:.metadata.name,R:.status.containerStatuses[0].ready,NODE:.spec.nodeName |
      awk '{split($1,a,"-"); w=($3=="ent-worker"?"w1":"w" substr($3,11)); printf "%s/%s=%s ", a[1], w, ($2=="true"?"R":"-")}')"
    sleep 2
  done ) > "$OUT/readiness.log" 2>&1 & pids+=($!)
BASE_URL=$GW RATE=$RATE DURATION=${SECS}s MAX_VUS=600 SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6-full.txt" 2>&1
sleep 20   # let readiness settle and capture the recovery
kill "${pids[@]}" 2>/dev/null; wait 2>/dev/null
end=$(date -u +%FT%TZ)
docker logs "$LB" --since "$start" --until "$end" 2>&1 |
  grep -E 'Too many open files|Caught Segmentation fault|starting main dispatch loop' | cut -c1-160 > "$OUT/lb-events.log"
echo "window $start .. $end"
echo "envoy crashes during the run: $(( $(docker logs "$LB" 2>&1 | grep -c 'Caught Segmentation fault') - crashes_before ))"
echo "first events:"; head -4 "$OUT/lb-events.log"
grep -vE 'Request Failed' "$OUT/k6-full.txt" > "$OUT/k6.txt"
echo "k6 summary:"; cat "$OUT/k6.txt"
echo "k6 network errors: $(grep -c 'Request Failed' "$OUT/k6-full.txt")"
grep -o 'error="[^"]*' "$OUT/k6-full.txt" | sed -E 's/.*: //' | sort | uniq -c | sort -rn | head -4
rm -f "$OUT/k6-full.txt"
echo "readiness (R = ready, - = not ready), every 2 s:"
awk '{printf "%s ", $1; for (i=2;i<=NF;i++) if ($i ~ /-$/) printf "%s ", $i; print ""}' "$OUT/readiness.log" |
  awk '{line=$0; sub(/^[^ ]+ /,"",line); if (line != prev) {print; prev=line}}'
for n in ent-worker ent-worker2 ent-worker3; do
  f="$RAW/ztunnel-$n.log"
  grep -E 'error=|warn|WARN' "$f" | head -300 > "$OUT/ztunnel-$n-errors.log"
  echo "ztunnel on $n: $(wc -l < "$f") lines, $(grep -c 'error=' "$f") with error=, by error:"
  grep -o 'error="[^"]*"' "$f" | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/ADDR/g' |
    sort | uniq -c | sort -rn | head -5
done
rm -rf "$RAW"
