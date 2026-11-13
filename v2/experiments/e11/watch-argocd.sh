#!/usr/bin/env bash
# E11 I4 (chapter 12): watch Argo CD sync itself after a merge - every change of the application
# argocd (revision, sync, health, operation) and of its pods, until it is Synced and Healthy at the
# expected chart version with all pods ready, or 15 minutes have passed.
#   bash v2/experiments/e11/watch-argocd.sh <chart version>
set -uo pipefail
WANT=${1:?chart version}
T0=$(date +%s); prev=""
pods() { kubectl -n argocd get pods --no-headers 2>/dev/null | awk '$3 != "Completed" {n++; split($2, a, "/"); if (a[1] == a[2] && $3 == "Running") r++} END {printf "%d/%d pods ready", r, n}'; }
while [ $(( $(date +%s) - T0 )) -lt 900 ]; do
  s=$(kubectl -n argocd get application argocd -o jsonpath='{.status.sync.revisions[0]} {.status.sync.status} {.status.health.status} {.status.operationState.phase}' 2>/dev/null)
  line="$s; $(pods)"
  [ "$line" != "$prev" ] && echo "  +$(( $(date +%s) - T0 )) s $(date -u +%T): chart $line"
  prev=$line
  set -- $s
  [ "${1:-}" = "$WANT" ] && [ "${2:-}" = Synced ] && [ "${3:-}" = Healthy ] && [ "${4:-}" = Succeeded ] &&
    kubectl -n argocd get pods --no-headers | awk '$3 != "Completed"' | awk '{split($2, a, "/"); if (a[1] != a[2] || $3 != "Running") bad++} END {exit bad > 0}' && break
  sleep 3
done
echo "  operation: $(kubectl -n argocd get application argocd -o jsonpath='{.status.operationState.message} (started {.status.operationState.startedAt}, finished {.status.operationState.finishedAt})')"
kubectl -n argocd get pods -o json | jq -r '.items[] | "    \(.metadata.name) started \(.status.startTime) restarts \([.status.containerStatuses[]?.restartCount] | add)"'
echo "  applications: $(kubectl -n argocd get applications --no-headers | awk '{print $2"/"$3}' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
