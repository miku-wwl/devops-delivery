#!/usr/bin/env bash
# Node-pressure eviction: which pod goes first, and when.
#   bash v2/experiments/e4/eviction.sh <label> <node>
# On one worker, in namespace e4-evict, three pods bound with nodeName (this skips the scheduler,
# not the kubelet's own admission check):
#   guaranteed  requests = limits (50m, 128Mi), holds 80 MiB                       Guaranteed
#   burst-hog   requests 64Mi, no limit; holds 100 MiB, grows 4 MiB/s              Burstable
#   be-hog      no requests; holds 150 MiB, grows 3 MiB/s only once signalled      BestEffort
# The kubelet ranks pods for memory eviction by (1) working set above the request or not,
# (2) priority, (3) working set minus request - not by QoS class (evict_rank.py). Prediction
# (evidence/e4/eviction-prediction.md): burst-hog goes first, although be-hog is BestEffort;
# be-hog goes second, after the script has signalled it to grow; everything else survives.
# While the node reports MemoryPressure, a probe pod (BestEffort, nodeName) tests the kubelet's
# admission. The kubelet of this lab evicts when memory.available < 12720Mi, i.e. when the node's
# working set passes ~2922 MiB (chapter 1); the node container's hard limit is 3072 MiB, and the
# growth rates keep the overshoot between two eviction checks (10 s) below the ~150 MiB left.
# Records every ~2 s: memory.available, MemoryPressure, the taint, pod states and pod memory.
# Deletes the namespace at the end; MemoryPressure stays set for the kubelet's transition period
# (5 min) after the last observed pressure - the script waits for it.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; NODE=${2:?node}; OUT="$ROOT/v2/evidence/e4/$LABEL"; mkdir -p "$OUT"
NS=e4-evict
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
tmp=$(mktemp -d); watcher=
trap '[ -n "$watcher" ] && kill $watcher 2>/dev/null; rm -rf "$tmp"; kubectl delete ns $NS --wait=false >/dev/null 2>&1' EXIT
T0=$(date -u +%FT%TZ)
kubectl get --raw "/api/v1/nodes/$NODE/proxy/configz" | jq -r --arg n "$NODE" '.kubeletconfig |
  "== kubelet on \($n): evictionHard memory.available < \(.evictionHard["memory.available"]), minimum reclaim \(.evictionMinimumReclaim["memory.available"] // "-"), pressure transition period \(.evictionPressureTransitionPeriod)"'
rank() {   # extra args for evict_rank.py
  kubectl get node "$NODE" -o json > "$tmp/node.json"
  kubectl get pods -A --field-selector spec.nodeName="$NODE" -o json > "$tmp/pods.json"
  kubectl get --raw "/api/v1/nodes/$NODE/proxy/stats/summary" > "$tmp/summary.json"
  python3 "$HERE/evict_rank.py" "$tmp/node.json" "$tmp/pods.json" "$tmp/summary.json" "$@"
}
restarts() {
  kubectl get pods -A --field-selector spec.nodeName="$NODE" -o json |
    jq -r --arg ns $NS '.items[] | select(.metadata.namespace != $ns) | "\(.metadata.namespace)/\(.metadata.name) \(.status.phase) restarts=\([.status.containerStatuses[]?.restartCount] | add // 0)"' | sort
}
echo "== before: the kubelet's memory-eviction ranking on $NODE (top 6)"
rank --top 6 --need 200 || { echo "less than 200 MiB free for admission on $NODE - not started"; exit 1; }
restarts > "$tmp/before"
kubectl create ns $NS >/dev/null
HOG='import os, signal, time
rate, cap, hold = int(os.environ["MIB_PER_S"]), int(os.environ["CAP_MIB"]), int(os.environ["HOLD_MIB"])
grow = os.environ.get("WAIT_SIGNAL") != "1"
def start(*_):
    global grow
    grow = True
signal.signal(signal.SIGUSR1, start)
blocks = [bytearray(b"x" * (1 << 20)) for _ in range(hold)]
print(time.strftime("%T"), "holding", hold, "MiB", flush=True)
while not grow:
    time.sleep(0.2)
print(time.strftime("%T"), "growing", rate, "MiB/s", flush=True)
while len(blocks) < cap and rate > 0:
    t = time.time()
    blocks.extend(bytearray(b"x" * (1 << 20)) for _ in range(rate))
    time.sleep(max(0.0, 1 - (time.time() - t)))
print(time.strftime("%T"), "done at", len(blocks), "MiB", flush=True)
while True:
    time.sleep(3600)'
pod() {   # name MiB/s cap-MiB hold-MiB wait-for-signal(0/1) resources-json
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
      env: [{name: MIB_PER_S, value: "$2"}, {name: CAP_MIB, value: "$3"}, {name: HOLD_MIB, value: "$4"}, {name: WAIT_SIGNAL, value: "$5"}]
      resources: $6
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
YAML
}
sample() {
  local s p c t
  s=$(kubectl get --raw "/api/v1/nodes/$NODE/proxy/stats/summary" 2>/dev/null)
  p=$(kubectl -n $NS get pods --no-headers -o custom-columns='N:.metadata.name,P:.status.phase,R:.status.reason,T:.status.containerStatuses[0].state.terminated.reason' 2>/dev/null |
      awk '{s = $1 ":" $2; if ($3 != "<none>") s = s "/" $3; if ($4 != "<none>") s = s "/" $4; printf "%s ", s}')
  c=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}')
  t=$(kubectl get node "$NODE" -o jsonpath='{.spec.taints[*].key}' | tr ' ' '\n' | grep -c memory-pressure)
  printf "%s avail=%sMiB ws=%sMiB | pressure=%s taint=%s | %s| %s\n" "$(date -u +%T)" \
    "$(jq -r '(.node.memory.availableBytes // 0) / 1048576 | floor' <<<"$s")" \
    "$(jq -r '(.node.memory.workingSetBytes // 0) / 1048576 | floor' <<<"$s")" "$c" "$t" "$p" \
    "$(jq -r --arg ns $NS '[.pods[] | select(.podRef.namespace == $ns) | "\(.podRef.name)=\(((.memory.workingSetBytes // 0) / 1048576) | floor)"] | sort | join(" ")' <<<"$s")"
}
phase() { kubectl -n $NS get pod "$1" -o jsonpath='{.status.phase}' 2>/dev/null; }
why() { kubectl -n $NS get pod "$1" -o jsonpath='{.status.phase}{"/"}{.status.reason}{"/"}{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null; }
pressure() { kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].status}'; }
pod guaranteed 0 80 80 0 '{"requests": {"cpu": "50m", "memory": "128Mi"}, "limits": {"cpu": "50m", "memory": "128Mi"}}'
pod burst-hog 4 1500 100 0 '{"requests": {"memory": "64Mi"}}'
pod be-hog 3 1500 150 1 '{}'
( while true; do sample; sleep 2; done ) > "$OUT/watch.txt" 2>&1 &
watcher=$!
for i in $(seq 1 45); do   # all three running, at most 90 s
  [ "$(phase guaranteed)$(phase burst-hog)$(phase be-hog)" = RunningRunningRunning ] && break; sleep 2
done
kubectl -n $NS get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass,PHASE:.status.phase,REASON:.status.reason --no-headers | sed 's/^/  /'
[ "$(phase guaranteed)$(phase burst-hog)$(phase be-hog)" = RunningRunningRunning ] || { echo "not all pods running - stopped"; exit 1; }
echo "$(date -u +%T) all three pods running; burst-hog grows, be-hog holds"
first=
for i in $(seq 1 180); do   # until one hog stops running, at most 6 minutes
  for h in burst-hog be-hog; do [ -z "$first" ] && [ "$(phase $h)" != Running ] && first=$h; done
  [ -n "$first" ] && break; sleep 2
done
[ -n "$first" ] || { echo "no hog stopped within 6 minutes - stopped"; exit 1; }
echo "$(date -u +%T) first to stop: $first ($(why $first))"
for i in $(seq 1 15); do [ "$(pressure)" = True ] && break; sleep 2; done
echo "$(date -u +%T) node MemoryPressure=$(pressure); probe: a BestEffort pod bound to $NODE"
PROBE=$(jq -cn --arg node "$NODE" --arg img "$IMG" '{spec: {nodeName: $node,
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: "RuntimeDefault"}},
  containers: [{name: "be-probe", image: $img, command: ["python", "-c", "import time; time.sleep(3600)"],
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}, readOnlyRootFilesystem: true}}]}}')
kubectl -n $NS run be-probe --image="$IMG" --restart=Never --overrides="$PROBE" >/dev/null
sleep 8
echo "  be-probe: $(why be-probe) - $(kubectl -n $NS get pod be-probe -o jsonpath='{.status.message}')"
second=$([ "$first" = burst-hog ] && echo be-hog || echo burst-hog)
if [ "$second" = be-hog ]; then
  kubectl -n $NS exec be-hog -- python -c 'import os, signal; os.kill(1, signal.SIGUSR1)' &&
    echo "$(date -u +%T) be-hog signalled: grows 3 MiB/s from now"
fi
for i in $(seq 1 180); do [ "$(phase $second)" != Running ] && break; sleep 2; done
echo "$(date -u +%T) second to stop: $second ($(why $second))"
sleep 6
kill $watcher 2>/dev/null; watcher=
echo "== timeline (lines where pressure, taint or a pod state changed, and every 20 s)"
awk -F' [|] ' '{sig = $2 " " $3} sig != prev || NR % 10 == 1 {print; prev = sig}' "$OUT/watch.txt"
echo "== lowest memory.available sampled: $(sed -n 's/.* avail=\([0-9]*\)MiB.*/\1/p' "$OUT/watch.txt" | sort -n | head -1) MiB (threshold 12720 MiB)"
echo "== pods in $NS at the end"
kubectl -n $NS get pods -o json |
  jq -r '.items[] | "  \(.metadata.name) \(.status.qosClass) \(.status.phase)/\(.status.reason // "-"): \(.status.message // "-")"'
for p in guaranteed burst-hog be-hog; do echo "  log $p: $(kubectl -n $NS logs $p 2>&1 | tr '\n' ';' | cut -c1-200)"; done
echo "== events in $NS"
kubectl -n $NS get events -o json |
  jq -r '.items | sort_by(.lastTimestamp // .eventTime) | .[] | select(.reason | test("Evicted|Killing|OOM|Preempt|Failed")) | "  \((.lastTimestamp // .eventTime) | .[11:19]) \(.involvedObject.name) \(.reason): \(.message)"' |
  cut -c1-330 | tee "$OUT/events.txt"
echo "== node events since the start"
kubectl get events -n default --field-selector involvedObject.kind=Node,involvedObject.name="$NODE" -o json |
  jq -r --arg t0 "$T0" '.items | sort_by(.lastTimestamp // .eventTime) | .[] | select(((.lastTimestamp // .eventTime) // "") >= $t0) | "  \((.lastTimestamp // .eventTime) | .[11:19]) \(.reason) x\(.count // 1): \(.message)"'
echo "== Evicted events outside $NS since the start: $(kubectl get events -A -o json | jq --arg t0 "$T0" --arg ns $NS '[.items[] | select(.reason == "Evicted" and .metadata.namespace != $ns and (((.lastTimestamp // .eventTime) // "") >= $t0))] | length')"
echo "== other pods on $NODE whose phase or restart count changed during the run"
restarts > "$tmp/after"
diff "$tmp/before" "$tmp/after" && echo "  none"
echo "== after: ranking on $NODE (top 4)"
rank --top 4
echo "== waiting for MemoryPressure to clear"
for i in $(seq 1 120); do [ "$(pressure)" = False ] && break; sleep 5; done
echo "  $(date -u +%T) MemoryPressure=$(pressure), since $(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="MemoryPressure")].lastTransitionTime}'); taints: $(kubectl get node "$NODE" -o jsonpath='{.spec.taints}')"
