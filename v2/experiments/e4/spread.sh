#!/usr/bin/env bash
# Topology spread over the three [模拟] zones while one zone cannot take new pods.
#   bash v2/experiments/e4/spread.sh <node-to-cordon>
# Cordons one worker (its zone keeps its running pods but gets no new ones), then deploys three
# variants of a 3-replica pause Deployment in namespace e4-spread:
#   soft   whenUnsatisfiable: ScheduleAnyway   (what the storefront chart uses)
#   hard   whenUnsatisfiable: DoNotSchedule    (nodeTaintsPolicy default: Ignore)
#   honor  DoNotSchedule + nodeTaintsPolicy: Honor
# and shows where the pods landed. Then uncordons the node and shows what happens to the pod
# that could not be placed. The node is uncordoned and the namespace deleted at the end.
set -uo pipefail
NODE=${1:?node to cordon}; NS=e4-spread
trap 'kubectl uncordon '"$NODE"' >/dev/null 2>&1; kubectl delete ns '"$NS"' --wait=false >/dev/null 2>&1' EXIT
kubectl create ns $NS >/dev/null
echo "== zones: $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o custom-columns=N:.metadata.name,Z:.metadata.labels.topology\\.kubernetes\\.io/zone --no-headers | tr '\n' ' ')"
kubectl cordon "$NODE"
dep() {   # name whenUnsatisfiable [nodeTaintsPolicy]
  kubectl -n $NS apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: $1}
spec:
  replicas: 3
  selector: {matchLabels: {app: $1}}
  template:
    metadata: {labels: {app: $1}}
    spec:
      terminationGracePeriodSeconds: 2
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: $2
          labelSelector: {matchLabels: {app: $1}}
          ${3:+nodeTaintsPolicy: $3}
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {memory: 16Mi}}
YAML
}
dep soft ScheduleAnyway
dep hard DoNotSchedule
dep honor DoNotSchedule Honor
sleep 20
show() { for d in soft hard honor; do
  echo "  $d: $(kubectl -n $NS get pods -l app=$d --no-headers -o custom-columns=P:.status.phase,N:.spec.nodeName | awk '{n = ($2 == "<none>" ? "unscheduled" : $2); c[$1 " on " n]++} END {for (k in c) printf "%s x%d; ", k, c[k]}')"
done; }
echo "== with $NODE cordoned"; show
echo "== why the pending pod is pending"
kubectl -n $NS get events --field-selector reason=FailedScheduling -o custom-columns=OBJ:.involvedObject.name,MSG:.message --no-headers | head -2 | cut -c1-260
t=$(date -u +%T); kubectl uncordon "$NODE"; echo "== $t uncordoned"
sleep 20; echo "== 20 s later"; show
kubectl -n $NS get events --sort-by=.lastTimestamp -o custom-columns=TIME:.lastTimestamp,OBJ:.involvedObject.name,REASON:.reason --no-headers | grep -E "hard-.*Scheduled" | tail -3
