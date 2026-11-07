#!/usr/bin/env bash
# Wait until an Argo CD application is Synced + Healthy at a given Git revision and
# print every state change with a timestamp (seconds since start).
#   bash delivery/argocd/wait-sync.sh <app> [revision] [timeout-seconds]
# revision defaults to the last merge made by promote.sh (~/work/last-merge-sha).
set -euo pipefail
app="${1:?usage: wait-sync.sh <app> [revision] [timeout]}"
want="${2:-$(cat "$HOME/work/last-merge-sha" 2>/dev/null || true)}"
timeout="${3:-240}"
start=$(date +%s)
last=""
while :; do
  IFS=$'\t' read -r rev sync health op < <(
    argocd app get "$app" --grpc-web -o json |
      jq -r '[.status.sync.revision[0:7], .status.sync.status, .status.health.status,
              (.status.operationState.phase // "-")] | @tsv')
  t=$(( $(date +%s) - start ))
  state="revision=$rev sync=$sync health=$health operation=$op"
  [ "$state" != "$last" ] && { echo "t+${t}s  $state"; last="$state"; }
  if [[ -z "$want" || "$rev" == "${want:0:7}" ]] && [ "$sync" = Synced ] && [ "$health" = Healthy ]; then
    echo "reached Synced/Healthy at ${rev} after ${t}s"
    exit 0
  fi
  [ "$t" -ge "$timeout" ] && { echo "timeout after ${t}s" >&2; exit 1; }
  sleep 3
done
