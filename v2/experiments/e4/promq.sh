#!/usr/bin/env bash
# Instant Prometheus query, one line per series: its labels and the value (3 decimals).
#   bash v2/experiments/e4/promq.sh <time: RFC3339 with Z, or epoch seconds> '<PromQL>'
set -euo pipefail
T=${1:?time}; Q=${2:?query}
[[ "$T" =~ ^[0-9]+$ ]] || T=$(date -d "$T" +%s)
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
kubectl get --raw "$P/query?time=$T&query=$(jq -rn --arg q "$Q" '$q|@uri')" |
  jq -r '.data.result | sort_by(-(.value[1] | tonumber)) | .[] |
    "  \(.metric | del(.__name__) | to_entries | map("\(.key)=\(.value)") | join(",")) \(.value[1] | tonumber | . * 1000 | round / 1000)"'
