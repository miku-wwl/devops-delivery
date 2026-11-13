#!/usr/bin/env bash
# Warnings and errors of storefront services in a time window, from Loki, summarised.
#   bash v2/experiments/e3/warn-logs.sh <start-iso> <end-iso> <service-regex>
# One line per distinct (second, pod, message, key) with its count; product keys are folded.
set -euo pipefail
S=${1:?start}; E=${2:?end}; SVC=${3:?service regex}
L=/api/v1/namespaces/observability/services/loki:3100/proxy/loki/api/v1
q="{service_name=~\"$SVC\"} | severity_text=~\"WARN|ERROR\""
kubectl get --raw "$L/query_range?query=$(jq -rn --arg q "$q" '$q|@uri')&start=$S&end=$E&limit=2000&direction=forward" |
  jq -r '.data.result[] | .stream as $s | .values[] |
    "\(.[0] | tonumber / 1e9 | strftime("%H:%M:%S"))|\($s.k8s_pod_name)|\(.[1])|\(($s.key // "") | sub(":sku-[0-9]+$"; ":sku-*"))"' |
  sort | awk -F'|' '{k = $1 " " $2 " " $3 (length($4) ? " [" $4 "]" : "")
    c[k]++; if (!(k in seen)) {seen[k] = 1; order[++n] = k}} END {for (i = 1; i <= n; i++) print c[order[i]] "x", order[i]}'
