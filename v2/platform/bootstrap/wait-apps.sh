#!/usr/bin/env bash
# Wait until every Argo CD application is Synced and Healthy, printing a line whenever the
# picture changes (a timeline of the platform converging from Git).
#   bash v2/platform/bootstrap/wait-apps.sh [timeout-seconds]
set -uo pipefail
timeout=${1:-1200}
start=$(date +%s)
last=""
while :; do
  now=$(( $(date +%s) - start ))
  rows=$(kubectl -n argocd get applications -o json 2>/dev/null |
    jq -r '.items[] | "\(.metadata.name)=\(.status.sync.status // "-")/\(.status.health.status // "-")"' | sort)
  total=$(wc -l <<<"$rows")
  good=$(grep -c '=Synced/Healthy$' <<<"$rows")
  summary="$good/$total Synced+Healthy; not yet: $(grep -v '=Synced/Healthy$' <<<"$rows" | tr '\n' ' ')"
  if [ "$summary" != "$last" ]; then
    printf 't+%4ss  %s\n' "$now" "$summary"
    last="$summary"
  fi
  if [ "$total" -gt 1 ] && [ "$good" -eq "$total" ]; then
    echo "all $total applications Synced and Healthy after ${now}s"
    exit 0
  fi
  if [ "$now" -ge "$timeout" ]; then
    echo "timeout after ${timeout}s" >&2
    exit 1
  fi
  sleep 5
done
