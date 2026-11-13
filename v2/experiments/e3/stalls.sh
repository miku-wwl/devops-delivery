#!/usr/bin/env bash
# Event-loop stalls (>= LOOP_STALL_MS, 250 ms) reported by the watchdog of one service, from Loki.
#   bash v2/experiments/e3/stalls.sh <start-iso> <end-iso> <service>
# Each report carries how long the loop was blocked, how much CPU the process and the loop
# thread used meanwhile, and how long the loop thread waited for a CPU (schedstat). A stall with
# cpu ~ blocked is the loop computing; one with a large runqueue is the thread not getting a CPU.
set -euo pipefail
S=$(date -u -d "${1:?start}" +%FT%TZ); E=$(date -u -d "${2:?end}" +%FT%TZ); SVC=${3:?service}   # RFC 3339 with Z: a "+" would be a space in the URL
L=/api/v1/namespaces/observability/services/loki:3100/proxy/loki/api/v1
kubectl get --raw "$L/query_range?query=$(jq -rn --arg q "{service_name=\"$SVC\"} |= \"event loop blocked\"" '$q|@uri')&start=$S&end=$E&limit=2000&direction=forward" |
  jq -r '.data.result[] | .stream | "\(.blocked_ms) \(.loop_thread_cpu_ms) \(.runqueue_ms)"' |
  awk '{n++; b += $1; c += $2; r += $3; if ($1 > mb) mb = $1; if ($3 > mr) mr = $3}
       END {if (!n) {print "no stalls"; exit}
            printf "%d stalls: blocked mean %.0f ms (max %.0f) | loop thread on a CPU %.0f ms | waiting for a CPU %.0f ms (max %.0f)\n",
                   n, b / n, mb, c / n, r / n, mr}'
