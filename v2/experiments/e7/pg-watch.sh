#!/usr/bin/env bash
# Once per second until killed: what CloudNativePG and Kubernetes say about pg-main (E7).
#   bash v2/experiments/e7/pg-watch.sh > watch.txt &
# Columns: UTC time, cluster phase, current/target primary, per instance "name:ready:role:node",
# the address behind the rw service, the nodes that are not Ready.
set -uo pipefail
while true; do
  t=$(date -u +%T)
  c=$(kubectl -n data get cluster pg-main -o json 2>/dev/null |
      jq -r '"\(.status.phase | gsub(" "; "_")) cur=\(.status.currentPrimary) tgt=\(.status.targetPrimary)"')
  p=$(kubectl -n data get pods -l cnpg.io/cluster=pg-main,cnpg.io/podRole=instance -o json 2>/dev/null |
      jq -r '[.items[] | "\(.metadata.name | ltrimstr("pg-main-")):\(if .metadata.deletionTimestamp then "del" else ([.status.conditions[]? | select(.type == "Ready") | .status][0] // "-" | .[0:1]) end):\(.metadata.labels["cnpg.io/instanceRole"] // "-" | .[0:1]):\(.spec.nodeName // "-" | ltrimstr("ent-"))"] | join(" ")')
  e=$(kubectl -n data get endpointslices -l kubernetes.io/service-name=pg-main-rw -o json 2>/dev/null |
      jq -r '[.items[].endpoints[]? | select(.conditions.ready) | .addresses[0]] | join(",") | if . == "" then "none" else . end')
  n=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {printf "%s:%s ", $1, $2}')
  echo "$t $c [$p] rw=$e ${n:+notready=$n}"
  sleep 1
done
