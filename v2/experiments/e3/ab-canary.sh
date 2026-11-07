#!/usr/bin/env bash
# Old and new build side by side, under the same traffic at the same time.
#   bash v2/experiments/e3/ab-canary.sh <label> <service> <new-tag> <rate> <seconds>
# Copies the service's Deployment as <service>-canary: one replica, image <new-tag>, the same
# labels plus track=canary, so the Service (and the mesh) send it the same share of traffic as
# each old pod. Runs the storefront mix at <rate> iterations/s for <seconds>, then compares the
# pods over the window (first 30 s skipped): requests/s, CPU, CPU per request, latency and
# event-loop lag. The two old pods are an A/A pair: their difference is the noise of the method.
# Drift (other load on the machine, caches, time of day) hits all pods alike, unlike an A-B-A
# sequence of separate runs. The copy is not in Git, Argo CD ignores it; it is deleted at the end.
# CANARY_NODE=<node> pins the canary to a node (e.g. next to an old pod: same cores, same time).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; SVC=${2:?service}; NEW=${3:?new image tag}; RATE=${4:?rate}; SECS=${5:?seconds}
OUT="$ROOT/v2/evidence/e3/$LABEL"; mkdir -p "$OUT"
NS=storefront
kubectl -n $NS get deploy "$SVC" -o json | jq --arg img "localhost:5001/storefront:$NEW" --arg name "$SVC-canary"   --arg node "${CANARY_NODE:-}" '
  {apiVersion, kind,
   metadata: {name: $name, namespace: .metadata.namespace,
              labels: (.metadata.labels + {track: "canary"} | del(.["app.kubernetes.io/managed-by"]))},
   spec: (.spec | .replicas = 1
     | .selector.matchLabels += {track: "canary"}
     | .template.metadata.labels += {track: "canary", "app.kubernetes.io/version": ($img | split(":")[-1])}
     | .template.spec.containers[0].image = $img
     | del(.template.metadata.annotations)
     | if $node != "" then .template.spec.nodeSelector = {"kubernetes.io/hostname": $node} else . end)}'   > "$OUT/canary-deployment.json"
trap 'kubectl -n $NS delete deploy "$SVC-canary" --ignore-not-found --wait=false >/dev/null' EXIT
kubectl apply -f "$OUT/canary-deployment.json"
kubectl -n $NS rollout status deploy/"$SVC-canary" --timeout=180s
sleep 20   # the canary's first requests (imports, connection pools) are not part of the window
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
  q "histogram_quantile(0.95, sum by (pod, le)(rate(http_server_request_duration_seconds_bucket{$sel}[${W}s])))" | sed 's/^/p95 /'
  q "histogram_quantile(0.99, sum by (pod, le)(rate(event_loop_lag_seconds_bucket{$sel}[${W}s])))" | sed 's/^/lag /'
} > "$OUT/per-pod.txt"
echo "window: $(date -u -d @$((start + 30)) +%T) .. $(date -u -d @$end +%T) (${W} s)"
printf "%-34s %-9s %7s %6s %10s %8s %8s %9s\n" pod image req/s cores "ms CPU/req" "p50 ms" "p95 ms" "lag p99"
awk 'NR == FNR {img[$1] = $3; sub(/.*:/, "", img[$1]); next}
     {v[$2, $1] = $3; pods[$2] = 1}
     END {
       for (p in pods) printf "%-34s %-9s %7.1f %6.3f %10.2f %8.1f %8.1f %9.1f\n", p, img[p], v[p, "rps"], v[p, "cpu"],
         (v[p, "rps"] > 0 ? 1000 * v[p, "cpu"] / v[p, "rps"] : 0), 1000 * v[p, "p50"], 1000 * v[p, "p95"], 1000 * v[p, "lag"]
     }' "$OUT/pods.txt" "$OUT/per-pod.txt" | sort -k2,2 -k1,1
