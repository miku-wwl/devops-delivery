#!/usr/bin/env bash
# Priority and preemption, with a timeline.
#   bash v2/experiments/e4/preemption.sh <label>
# In namespace e4-sched: two PriorityClasses (e4-batch-low -10, e4-critical 100000), then
#   1. "filler": pause pods of e4-batch-low, 1 CPU requested each, as many as fit on the three
#      workers (the scheduler packs them until the next one stays Pending);
#   2. "critical": 2 pause pods of e4-critical, 1 CPU each - no room, so the scheduler must evict
#      (preempt) lower-priority pods; it nominates a node, the victims get a graceful termination,
#      and the critical pod binds once they are gone.
# Pause containers use no CPU: they only reserve it, so the running services are not slowed down.
# The batch class is below 0 on purpose: pods without a PriorityClass (all storefront services)
# have priority 0, and the scheduler preempts the lowest priorities first - with batch at +100,
# the victims would have been storefront pods, not the batch pods.
# Records every pod's creation/scheduling/deletion and the events, then deletes the namespace
# and the PriorityClasses.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; OUT="$ROOT/v2/evidence/e4/$LABEL"; mkdir -p "$OUT"
NS=e4-sched
PAUSE=registry.k8s.io/pause:3.10
cleanup() { kubectl delete ns $NS --wait=false >/dev/null 2>&1; kubectl delete priorityclass e4-batch-low e4-critical >/dev/null 2>&1; }
trap cleanup EXIT
kubectl create ns $NS >/dev/null
kubectl apply -f - >/dev/null <<YAML
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: {name: e4-batch-low}
value: -10                        # below the default 0 of every pod without a class: batch never
preemptionPolicy: Never           # outranks the services, and never evicts anything itself
description: "E4: batch work that may be preempted"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: {name: e4-critical}
value: 100000
description: "E4: work that preempts batch"
YAML
deploy() {   # name priorityclass replicas
  kubectl -n $NS apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $1}
spec:
  replicas: $3
  selector: {matchLabels: {app: $1}}
  template:
    metadata: {labels: {app: $1}}
    spec:
      priorityClassName: $2
      terminationGracePeriodSeconds: 5
      nodeSelector: {kubernetes.io/os: linux}
      tolerations: []
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms: [{matchExpressions: [{key: node-role.kubernetes.io/control-plane, operator: DoesNotExist}]}]
      containers:
        - name: pause
          image: $PAUSE
          resources: {requests: {cpu: "1", memory: 8Mi}, limits: {memory: 16Mi}}
YAML
}
echo "== free CPU on the workers before (allocatable - requested)"
kubectl describe nodes -l '!node-role.kubernetes.io/control-plane' | awk '/^Name:/ {n = $2} /^Allocatable:/ {a = 1} a && /cpu:/ {alloc[n] = $2; a = 0} /^  cpu  / {print "  " n ": allocatable " alloc[n] ", requested " $2 " " $3}'
deploy filler e4-batch-low 12
for i in $(seq 1 30); do
  pend=$(kubectl -n $NS get pods -l app=filler --field-selector status.phase=Pending --no-headers 2>/dev/null | wc -l)
  run=$(kubectl -n $NS get pods -l app=filler --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l)
  [ $((pend + run)) -ge 12 ] && [ "$run" -gt 0 ] && sleep 5 && break; sleep 2
done
echo "== filler: $(kubectl -n $NS get pods -l app=filler --field-selector status.phase=Running --no-headers | wc -l) running, $(kubectl -n $NS get pods -l app=filler --field-selector status.phase=Pending --no-headers | wc -l) pending (no CPU left)"
kubectl -n $NS get pods -l app=filler -o wide --no-headers | awk '{print "  " $1, $3, $7}'
t0=$(date -u +%FT%TZ); echo "== $t0 critical: 2 pods of priority 100000"
deploy critical e4-critical 2
for i in $(seq 1 60); do
  [ "$(kubectl -n $NS get pods -l app=critical --field-selector status.phase=Running --no-headers 2>/dev/null | wc -l)" -ge 2 ] && break; sleep 1
done
sleep 10
echo "== critical pods: created, nominated node, scheduled, running"
kubectl -n $NS get pods -l app=critical -o json | jq -r '.items[] | [.metadata.name, .metadata.creationTimestamp,
  (.status.nominatedNodeName // "-"), .spec.nodeName,
  ((.status.conditions // [])[] | select(.type == "PodScheduled") | .lastTransitionTime),
  ((.status.conditions // [])[] | select(.type == "Ready") | .lastTransitionTime)] | @tsv' | tee "$OUT/critical.txt"
echo "== events in order (scheduling, preemption, killing)"
kubectl -n $NS get events --sort-by=.lastTimestamp -o custom-columns=TIME:.lastTimestamp,OBJ:.involvedObject.name,REASON:.reason,MSG:.message |
  grep -E "Preempt|FailedScheduling|Scheduled|Killing|SuccessfulCreate" | awk -v t="$t0" '$1 >= t' | tee "$OUT/events.txt" | head -40
echo "== filler afterwards: $(kubectl -n $NS get pods -l app=filler --field-selector status.phase=Running --no-headers | wc -l) running, $(kubectl -n $NS get pods -l app=filler --field-selector status.phase=Pending --no-headers | wc -l) pending"
