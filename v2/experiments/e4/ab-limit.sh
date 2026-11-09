#!/usr/bin/env bash
# A CPU limit side by side (E4, chapter 5): one copy of the service's Deployment with a CPU limit
# next to the unlimited pods, under the same traffic at the same time.
#   bash v2/experiments/e4/ab-limit.sh <label> <service> <cpu-limit> <rate> <seconds>
# The copy (<service>-limited, one replica, same image and labels plus track=limited) gets a CFS
# quota: <cpu-limit> of CPU time per 100 ms period (its request is set to the same value: a
# request above the limit is invalid). Compares the pods over the window (first 30 s
# skipped): requests/s, CPU, latency (p50, p99), event-loop lag and the share of CFS periods in
# which the pod was throttled, and reads the kernel's own counters (cpu.stat) of the limited
# pod's cgroup before and after. The copy is not in Git (Argo CD ignores it); deleted at the end.
# CANARY_NODE=<node> pins the canary to a node (e.g. next to an old pod: same cores, same time).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; SVC=${2:?service}; LIMIT=${3:?cpu limit}; RATE=${4:?rate}; SECS=${5:?seconds}
OUT="$ROOT/v2/evidence/e4/$LABEL"; mkdir -p "$OUT"
NS=storefront
kubectl -n $NS get deploy "$SVC" -o json | jq --arg limit "$LIMIT" --arg name "$SVC-limited"   --arg node "${CANARY_NODE:-}" '
  {apiVersion, kind,
   metadata: {name: $name, namespace: .metadata.namespace,
              labels: (.metadata.labels + {track: "limited"} | del(.["app.kubernetes.io/managed-by"]))},
   spec: (.spec | .replicas = 1
     | .selector.matchLabels += {track: "limited"}
     | .template.metadata.labels += {track: "limited"}
     | .template.spec.containers[0].resources.limits.cpu = $limit
     | .template.spec.containers[0].resources.requests.cpu = $limit
     | del(.template.metadata.annotations)
     | if $node != "" then .template.spec.nodeSelector = {"kubernetes.io/hostname": $node} else . end)}'   > "$OUT/limited-deployment.json"
trap 'kubectl -n $NS delete deploy "$SVC-limited" --ignore-not-found --wait=false >/dev/null' EXIT
kubectl apply -f "$OUT/limited-deployment.json"
kubectl -n $NS rollout status deploy/"$SVC-limited" --timeout=180s
sleep 20   # the copy's first requests (imports, connection pools) are not part of the window
LPOD=$(kubectl -n $NS get pods -l app.kubernetes.io/name="$SVC",track=limited -o jsonpath='{.items[0].metadata.name}')
LNODE=$(kubectl -n $NS get pod "$LPOD" -o jsonpath='{.spec.nodeName}')
CID=$(kubectl -n $NS get pod "$LPOD" -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's|.*://||')
CG=$(docker exec "$LNODE" sh -c "crictl inspect $CID | jq -r .info.runtimeSpec.linux.cgroupsPath")
cpustat() { docker exec "$LNODE" sh -c "f=\$(find /sys/fs/cgroup -path '*${CG##*:}*' -name cpu.stat | head -1); cat /sys/fs/cgroup/\${f#/sys/fs/cgroup/}" 2>/dev/null |
  grep -E '^(nr_periods|nr_throttled|throttled_usec|usage_usec) ' | tr '
' ' '; }
echo "limited pod $LPOD on $LNODE, cpu.max: $(docker exec "$LNODE" sh -c "cat \$(find /sys/fs/cgroup -path '*${CG##*:}*' -name cpu.max | head -1)")"
echo "cpu.stat before: $(cpustat)"
kubectl -n $NS get pods -l app.kubernetes.io/name="$SVC" --no-headers \
  -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,IMAGE:.spec.containers[0].image | tee "$OUT/pods.txt"
bash "$ROOT/v2/platform/cluster/lb-limits.sh" > /dev/null
GW=http://$(kubectl -n $NS get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
start=$(date -u +%s)
BASE_URL=$GW RATE=$RATE DURATION=${SECS}s SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1 || true
end=$(date -u +%s)
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" > /dev/null
cat "$OUT/k6.txt"
echo "cpu.stat after:  $(cpustat)"
sleep 20   # let the last scrape cover the end of the window
# per pod, over the window without the first 30 s (the same table works for past windows)
bash "$HERE/pod-table.sh" "$SVC" "$(date -u -d @$((start + 30)) +%FT%TZ)" "$(date -u -d @$end +%FT%TZ)"
