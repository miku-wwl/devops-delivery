#!/usr/bin/env bash
# One line every ~2 s about a scaled workload: HPA decision, Deployment replicas, pod states.
#   bash v2/experiments/e4/watch.sh <deployment> [hpa-name] > timeline.txt   (stop with kill)
# Line: UTC time | hpa desired current cpu%-of-request | deploy spec ready | pods name:phase:ready
# (the pod name is shortened to its last 5 characters; a pod without a ready flag is still
# being created). Used to build the scale-up and scale-down timelines of chapter 5.
set -uo pipefail
D=${1:?deployment}; H=${2:-$1}; NS=${NS:-storefront}
while true; do
  t=$(date -u +%T)
  h=$(kubectl -n "$NS" get hpa "$H" -o jsonpath='{.status.desiredReplicas} {.status.currentReplicas} {.status.currentMetrics[0].resource.current.averageUtilization}{.status.currentMetrics[0].external.current.averageValue}' 2>/dev/null)
  d=$(kubectl -n "$NS" get deploy "$D" -o jsonpath='{.spec.replicas} {.status.readyReplicas}' 2>/dev/null)
  p=$(kubectl -n "$NS" get pods -l app.kubernetes.io/name="$D" --no-headers \
        -o custom-columns=N:.metadata.name,P:.status.phase,R:.status.containerStatuses[0].ready 2>/dev/null |
      awk '{printf "%s:%s:%s ", substr($1, length($1) - 4), $2, $3}')
  echo "$t | hpa ${h:-none} | deploy ${d:-?} | $p"
  sleep 2
done
