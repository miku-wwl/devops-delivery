#!/usr/bin/env bash
# Why increase() missed a burst of errors: counter series that are created by the burst itself.
#   bash v2/experiments/e3/first-sample.sh <start-iso> <end-iso> <service>
# For every 5xx series of the service: when Prometheus first saw it and with which value, its
# value at the end, and what increase() over the whole window reports. A series created by the
# first increment has no sample before it: increase() cannot see the jump from "no series" to
# its first value (prometheus_client creates a labelled child on first use).
set -euo pipefail
S=${1:?start}; E=${2:?end}; SVC=${3:?service}
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
sel="http_server_requests_total{service=\"$SVC\",code=~\"5..\"}"
kubectl get --raw "$P/query_range?query=$(jq -rn --arg q "$sel" '$q|@uri')&start=$S&end=$E&step=15s" |
  jq -r '.data.result[] | "\(.metric.pod[-5:]) \(.metric.route) \(.metric.code): first seen \(.values[0][0] | strftime("%H:%M:%S")) = \(.values[0][1]), at the end = \(.values[-1][1])"' | sort
w=$(( $(date -d "$E" +%s) - $(date -d "$S" +%s) ))
kubectl get --raw "$P/query?time=$E&query=$(jq -rn --arg q "sum by (route, code) (increase(${sel}[${w}s]))" '$q|@uri')" |
  jq -r '.data.result[] | "increase over the window: \(.metric.route) \(.metric.code) = \(.value[1] | tonumber | floor)"' | sort
