#!/usr/bin/env bash
# A CPU hog next to the services: who suffers, and how much do CPU requests protect them?
#   bash v2/experiments/e4/noisy.sh <label> <node> <rate> <seconds-per-phase>
# One k6 run at <rate> it/s through three phases of <seconds> each:
#   base     no hog
#   be       a BestEffort hog on <node>: 4 processes busy-looping (the node has 4 CPUs), no requests
#   burst    the same hog with requests.cpu 2 (Burstable)
# Under contention, the kernel shares CPU by cgroup weight, and the kubelet derives the weights
# from the CPU requests: BestEffort pods share the lowest-weight slice, a Burstable pod weighs in
# proportion to its request. The gateway requests 500m, the other services 50m. Per phase, for
# every pod of SERVICES: CPU, latency p50/p99 and event-loop lag p99 - the pods on <node> next to their
# siblings on other nodes (same time, same traffic). The hog pods are deleted at the end.
# SERVICES (a regex, default gateway|orders|inventory|payments) chooses the services compared.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; NODE=${2:?node}; RATE=${3:?rate}; SECS=${4:?seconds per phase}
OUT="$ROOT/v2/evidence/e4/$LABEL"; mkdir -p "$OUT"
NS=e4-noisy
SERVICES=${SERVICES:-gateway|orders|inventory|payments}
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
trap 'kubectl delete ns $NS --wait=false >/dev/null 2>&1' EXIT
kubectl create ns $NS >/dev/null
BURN='import multiprocessing, os
def burn():
    while True:
        pass
for _ in range(4):
    multiprocessing.Process(target=burn).start()'
hog() {   # name resources-json
  kubectl -n $NS apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $1}
spec:
  nodeName: $NODE
  terminationGracePeriodSeconds: 1
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: burn
      image: $IMG
      command: ["python", "-c", $(jq -rn --arg s "$BURN" '$s | @json')]
      resources: $2
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
YAML
}
kubectl -n storefront get pods -o wide --no-headers | awk -v n="$NODE" -v re="^($SERVICES)-" '$1 ~ re {print "  " $1, $7, ($7 == n ? "<- next to the hog" : "")}'
bash "$ROOT/v2/platform/cluster/lb-limits.sh" > /dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
t0=$(date -u +%s)
BASE_URL=$GW RATE=$RATE DURATION=$((3 * SECS + 20))s SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1 &
k6pid=$!
sleep "$SECS"; hog be '{}'; echo "$(date -u +%T) BestEffort hog started"
sleep "$SECS"; kubectl -n $NS delete pod be --wait=true >/dev/null; hog burst '{"requests": {"cpu": "2"}}'
echo "$(date -u +%T) BestEffort hog stopped, Burstable hog (requests 2 CPU) started"
sleep "$SECS"; kubectl -n $NS delete pod burst --wait=true >/dev/null; echo "$(date -u +%T) hog stopped"
wait $k6pid
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" > /dev/null; cat "$OUT/k6.txt"
sleep 20
for i in 0 1 2; do
  phase=$(echo base be burst | cut -d' ' -f$((i + 1))); end=$((t0 + (i + 1) * SECS))
  echo "=== phase $phase (pods on $NODE are next to the hog)"
  bash "$HERE/pod-table.sh" "$SERVICES" "$(date -u -d @$((end - SECS + 30)) +%FT%TZ)" "$(date -u -d @$end +%FT%TZ)"
done
echo "=== CPU weights of the cgroups on $NODE (cpu.weight; kubelet maps requests to weights)"
docker exec "$NODE" sh -c 'for d in /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/kubelet-kubepods-besteffort.slice /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/kubelet-kubepods-burstable.slice; do echo "  $(basename $d): $(cat $d/cpu.weight 2>/dev/null)"; done'
