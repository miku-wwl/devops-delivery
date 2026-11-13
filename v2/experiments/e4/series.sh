#!/usr/bin/env bash
# A few Prometheus series side by side, one row per step, for a time window (evidence tables).
#   bash v2/experiments/e4/series.sh <start-iso> <end-iso> <step-s> '<label>=<promql>' ...
set -euo pipefail
S=${1:?start}; E=${2:?end}; STEP=${3:?step}; shift 3
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
i=0; head="time"
for arg in "$@"; do
  label=${arg%%=*}; q=${arg#*=}; head="$head $label"
  kubectl get --raw "$P/query_range?query=$(jq -rn --arg q "$q" '$q|@uri')&start=$(date -d "$S" +%s)&end=$(date -d "$E" +%s)&step=$STEP" |
    jq -r '.data.result[0].values[]? | "\(.[0] | strftime("%H:%M:%S")) \(.[1] | tonumber | . * 100 | round / 100)"' > "$tmp/$i"
  i=$((i + 1))
done
echo "$head"
cut -d' ' -f1 "$tmp/0" | while read -r t; do
  row="$t"; for f in $(seq 0 $((i - 1))); do row="$row $(awk -v t="$t" '$1 == t {print $2}' "$tmp/$f")"; done; echo "$row"
done | column -t
