#!/usr/bin/env bash
# Node-pressure eviction: which pod goes first, and when.
#   bash v2/experiments/e4/eviction.sh <label> <node>
# On one worker (pinned with nodeName), in namespace e4-evict:
#   be-hog      BestEffort (no requests)            grows 5 MiB/s up to 1500 MiB
#   burst-hog   Burstable, requests 64Mi, no limit  holds 100 MiB, grows 2 MiB/s up to 1500 MiB
#   guaranteed  requests = limits 300Mi             holds 200 MiB (within its request)
# The kubelet of this lab evicts when memory.available < 12720Mi, i.e. when the node's working
# set passes ~2922 MiB (chapter 1); the node container's hard limit is 3 GiB. The growth rates
# keep the overshoot between two eviction checks (10 s) small. Should the 3 GiB limit be hit
# anyway, the kernel kills the process with the highest oom_score_adj: a BestEffort hog (1000),
# never kubelet (-999). Records every ~2 s: node working set, MemoryPressure, pod states; then
# the eviction events. Deletes the namespace at the end; MemoryPressure stays set for the
# kubelet's transition period (5 min) after the last eviction - the script waits for it.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; NODE=${2:?node}; OUT="$ROOT/v2/evidence/e4/$LABEL"; mkdir -p "$OUT"
NS=e4-evict
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
trap 'kubectl delete ns $NS --wait=false >/dev/null 2>&1' EXIT
kubectl create ns $NS >/dev/null
CAP=$(kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq -r '.kubeletconfig.evictionHard["memory.available"]')
echo "== $NODE: eviction when memory.available < $CAP; capacity $(kubectl get node $NODE -o jsonpath='{.status.capacity.memory}')"
HOG='import os, time
rate, cap, hold = float(os.environ["MIB_PER_S"]), int(os.environ["CAP_MIB"]), int(os.environ["HOLD_MIB"])
blocks = [bytearray(b"x" * (1 << 20)) for _ in range(hold)]
print("holding", hold, "MiB", flush=True)
while len(blocks) < cap and rate > 0:
    t = time.time()
    blocks.extend(bytearray(b"x" * (1 << 20)) for _ in range(int(rate)))
    time.sleep(max(0.0, 1 - (time.time() - t)))
print("done at", len(blocks), "MiB", flush=True)
time.sleep(10**9)'
pod() {   # name rate cap hold resources-json
  kubectl -n $NS apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $1, labels: {app: e4-hog}}
spec:
  nodeName: $NODE
  restartPolicy: Never
  terminationGracePeriodSeconds: 1
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: hog
      image: $IMG
      command: ["python", "-c", $(jq -rn --arg s "$HOG" '$s | @json')]
      env: [{name: MIB_PER_S, value: "$2"}, {name: CAP_MIB, value: "$3"}, {name: HOLD_MIB, value: "$4"}]
      resources: $5
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
YAML
}
ws() { kubectl get --raw "/api/v1/nodes/$NODE/proxy/stats/summary" | jq -r '.node.memory.workingSetBytes / 1048576 | floor'; }
echo "== node working set before: $(ws) MiB"
pod guaranteed 0 200 200 '{"requests": {"cpu": "50m", "memory": "300Mi"}, "limits": {"cpu": "50m", "memory": "300Mi"}}'
pod burst-hog 2 1500 100 '{"requests": {"memory": "64Mi"}}'
pod be-hog 5 1500 0 '{}'
kubectl -n $NS get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass --no-headers | sed 's/^/  /'
( while true; do
    p=$(kubectl -n $NS get pods --no-headers -o custom-columns=N:.metadata.name,P:.status.phase,R:.status.reason 2>/dev/null | awk '{printf "%s:%s%s ", $1, $2, ($3 == "<none>" ? "" : "/" $3)}')
    c=$(kubectl get node $NODE -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}')
    echo "$(date -u +%T) ws=$(ws)MiB pressure=$c $p"; sleep 2
  done ) > "$OUT/watch.txt" 2>&1 &
watcher=$!
for i in $(seq 1 360); do   # until both hogs are gone, at most 12 minutes
  left=$(kubectl -n $NS get pods --no-headers 2>/dev/null | grep -E "hog" | grep -c Running)
  [ "$left" -eq 0 ] && break; sleep 2
done
sleep 6
echo "== timeline: lines where the pressure flag or a pod state changed"
awk '{sig = $3; for (i = 4; i <= NF; i++) sig = sig " " $i} sig != prev {print; prev = sig}' "$OUT/watch.txt" | head -40
echo "== eviction events"
kubectl -n $NS get events --sort-by=.lastTimestamp -o custom-columns=TIME:.lastTimestamp,POD:.involvedObject.name,REASON:.reason,MSG:.message |
  grep -E "Evicted|Killing|OOM" | cut -c1-330 | tee "$OUT/events.txt"
kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name=$NODE --sort-by=.lastTimestamp \
  -o custom-columns=TIME:.lastTimestamp,REASON:.reason,MSG:.message | tail -5
echo "== other pods evicted on $NODE during the run: $(kubectl get events -A --field-selector reason=Evicted -o custom-columns=NS:.metadata.namespace,OBJ:.involvedObject.name --no-headers | grep -v "^$NS " | wc -l)"
kill $watcher 2>/dev/null
echo "== waiting for MemoryPressure to clear (kubelet transition period)"
for i in $(seq 1 120); do
  [ "$(kubectl get node $NODE -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}')" = "False" ] && break; sleep 5
done
echo "  $(date -u +%T) MemoryPressure=$(kubectl get node $NODE -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}'), taints: $(kubectl get node $NODE -o jsonpath='{.spec.taints}')"
