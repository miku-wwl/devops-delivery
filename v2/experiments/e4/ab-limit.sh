#!/usr/bin/env bash
# A CPU limit side by side (E4, chapter 5): one copy of the service's Deployment with a CPU limit
# next to the unlimited pods, under the same traffic at the same time.
#   bash v2/experiments/e4/ab-limit.sh <label> <service> <cpu-limit> <rate> <seconds>
# The copy (<service>-limited, one replica, same image and labels plus track=limited) gets a CFS
# quota: <cpu-limit> of CPU time per 100 ms period. Compares the pods over the window (first 30 s
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
W=$((end - start - 30))
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
q() { kubectl get --raw "$P/query?time=$end&query=$(jq -rn --arg q "$1" '$q|@uri')" |
  jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"'; }
sel="namespace=\"$NS\",pod=~\"$SVC-.*\""
{
  q "sum by (pod)(rate(http_server_requests_total{$sel}[${W}s]))" | sed 's/^/rps /'
  q "sum by (pod)(rate(container_cpu_usage_seconds_total{$sel,container=\"app\"}[${W}s]))" | sed 's/^/cpu /'
  q "histogram_quantile(0.5, sum by (pod, le)(rate(http_server_request_duration_seconds_bucket{$sel}[${W}s])))" | sed 's/^/p50 /'
  q "histogram_quantile(0.99, sum by (pod, le)(rate(http_server_request_duration_seconds_bucket{$sel}[${W}s])))" | sed 's/^/p95 /'
  q "histogram_quantile(0.99, sum by (pod, le)(rate(event_loop_lag_seconds_bucket{$sel}[${W}s])))" | sed 's/^/lag /'
  q "sum by (pod)(rate(container_cpu_cfs_throttled_periods_total{$sel,container=\"app\"}[${W}s])) / sum by (pod)(rate(container_cpu_cfs_periods_total{$sel,container=\"app\"}[${W}s]))" | sed 's/^/thr /'
} > "$OUT/per-pod.txt"
echo "window: $(date -u -d @$((start + 30)) +%T) .. $(date -u -d @$end +%T) (${W} s)"
printf "%-34s %-9s %7s %6s %10s %8s %8s %9s\n" pod image req/s cores "ms CPU/req" "p50 ms" "p95 ms" "lag p99"
awk 'NR == FNR {img[$1] = ($1 ~ /-limited-/ ? "'"$LIMIT"'" : "none"); next}
     {v[$2, $1] = $3; pods[$2] = 1}
     END {
       for (p in pods) printf "%-34s %-9s %7.1f %6.3f %10.2f %8.1f %8.1f %9.1f\n", p, img[p], v[p, "rps"], v[p, "cpu"],
         (v[p, "rps"] > 0 ? 1000 * v[p, "cpu"] / v[p, "rps"] : 0), 1000 * v[p, "p50"], 1000 * v[p, "p95"], 1000 * v[p, "lag"]
     }' "$OUT/pods.txt" "$OUT/per-pod.txt" | sort -k2,2 -k1,1
