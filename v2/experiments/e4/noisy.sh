#!/usr/bin/env bash
# A CPU hog next to the services: who suffers, and how much do CPU requests protect them?
#   bash v2/experiments/e4/noisy.sh <label> <node> <rate> <seconds-per-phase>
# One k6 run at <rate> it/s through three phases of <seconds> each:
#   base     no hog
#   be       a BestEffort hog on <node>: 4 processes busy-looping (the node has 4 CPUs), no requests
#   burst    the same hog with requests.cpu 2 (Burstable)
# Under contention, the kernel shares CPU by cgroup weight, and the kubelet derives the weights
# from the CPU requests: BestEffort pods share the lowest-weight slice, a Burstable pod weighs in
# proportion to its request. The gateway requests 500m, catalog 50m. Per phase, for every gateway
# and catalog pod: CPU, latency p50/p99 and event-loop lag p99 - the pods on <node> next to their
# siblings on other nodes (same time, same traffic). The hog pods are deleted at the end.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; NODE=${2:?node}; RATE=${3:?rate}; SECS=${4:?seconds per phase}
OUT="$ROOT/v2/evidence/e4/$LABEL"; mkdir -p "$OUT"
NS=e4-noisy
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
kubectl -n storefront get pods -o wide --no-headers | awk -v n="$NODE" '$1 ~ /^(gateway|catalog)-/ {print "  " $1, $7, ($7 == n ? "<- next to the hog" : "")}'
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
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
q() { kubectl get --raw "$P/query?time=$2&query=$(jq -rn --arg q "$1" '$q|@uri')" | jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"'; }
sel='namespace="storefront",pod=~"(gateway|catalog)-.*"'
W=$((SECS - 30))
for i in 0 1 2; do
  phase=$(echo base be burst | cut -d' ' -f$((i + 1))); end=$((t0 + (i + 1) * SECS))
  echo "=== phase $phase ($(date -u -d @$((end - W)) +%T) .. $(date -u -d @$end +%T))"
  {
    q "sum by (pod)(rate(container_cpu_usage_seconds_total{$sel,container=\"app\"}[${W}s]))" $end | sed 's/^/cpu /'
    q "histogram_quantile(0.5, sum by (pod, le)(rate(http_server_request_duration_seconds_bucket{$sel}[${W}s])))" $end | sed 's/^/p50 /'
    q "histogram_quantile(0.99, sum by (pod, le)(rate(http_server_request_duration_seconds_bucket{$sel}[${W}s])))" $end | sed 's/^/p99 /'
    q "histogram_quantile(0.99, sum by (pod, le)(rate(event_loop_lag_seconds_bucket{$sel}[${W}s])))" $end | sed 's/^/lag /'
  } > "$OUT/phase-$phase.txt"
  printf "  %-34s %-12s %6s %8s %8s %9s\n" pod node cores "p50 ms" "p99 ms" "lag p99"
  awk -v n="$NODE" 'NR == FNR {node[$1] = $7; next} {v[$2, $1] = $3; pods[$2] = 1}
    END {for (p in pods) printf "  %-34s %-12s %6.3f %8.1f %8.1f %9.1f%s\n", p, node[p], v[p, "cpu"], 1000 * v[p, "p50"],
         1000 * v[p, "p99"], 1000 * v[p, "lag"], (node[p] == n ? "  <- hog node" : "")}' \
    <(kubectl -n storefront get pods -o wide --no-headers) "$OUT/phase-$phase.txt" | sort
done
echo "=== CPU weights of the cgroups on $NODE (cpu.weight; kubelet maps requests to weights)"
docker exec "$NODE" sh -c 'for d in /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/kubelet-kubepods-besteffort.slice /sys/fs/cgroup/kubelet.slice/kubelet-kubepods.slice/kubelet-kubepods-burstable.slice; do echo "  $(basename $d): $(cat $d/cpu.weight 2>/dev/null)"; done'
