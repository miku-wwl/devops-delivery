#!/usr/bin/env bash
# Print every state change of an Argo Rollout (phase, step, replicas, background
# analysis) with a timestamp, until it reaches the wanted phase.
#   bash delivery/rollouts/watch-rollout.sh <namespace> <rollout> [Paused|Healthy|Degraded] [timeout-s]
set -euo pipefail
ns="${1:?namespace}" name="${2:?rollout}" until="${3:-Healthy}" timeout="${4:-300}"
start=$(date +%s); last=""
while :; do
  IFS=$'\t' read -r phase step updated available analysis msg < <(
    kubectl -n "$ns" get rollout "$name" -o json | jq -r '[
      .status.phase // "-",
      (.status.currentStepIndex // 0 | tostring),
      (.status.updatedReplicas // 0 | tostring),
      (.status.availableReplicas // 0 | tostring),
      (.status.canary.currentBackgroundAnalysisRunStatus.status // "-"),
      (.status.message // "-")] | @tsv')
  t=$(( $(date +%s) - start ))
  line="phase=$phase step=$step updated=$updated available=$available analysis=$analysis message=\"$msg\""
  [ "$line" != "$last" ] && { echo "t+${t}s  $line"; last="$line"; }
  [ "$phase" = "$until" ] && exit 0
  if [ "$phase" = "Degraded" ] && [ "$until" != "Degraded" ]; then exit 1; fi
  [ "$t" -ge "$timeout" ] && { echo "timeout after ${t}s" >&2; exit 1; }
  sleep 3
done
