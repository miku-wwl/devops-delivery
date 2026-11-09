#!/usr/bin/env bash
# Scale-up and scale-down timeline of the gateway's HorizontalPodAutoscaler under a load step.
#   bash v2/experiments/e4/hpa-timeline.sh <label> [low] [high] [low-s] [high-s] [after-s]
# Default: 30 it/s for 120 s, 120 it/s for 420 s, 30 it/s for 480 s (one k6 run, 10 s ramps).
# Records: the controllers' timing settings, a watcher line every ~2 s (watch.sh), k6 per
# stage, the HPA and pod events, and for every gateway pod its creation, scheduling, start and
# readiness times. Output: evidence/e4/<label>/.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; LOW=${2:-30}; HIGH=${3:-120}; T1=${4:-120}; T2=${5:-420}; T3=${6:-480}
OUT="$ROOT/v2/evidence/e4/$LABEL"; mkdir -p "$OUT"
NS=storefront
echo "== settings that bound the reaction time"
kubectl -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}' | tr ',' '\n' |
  grep -E "resolution|kubelet" | sed 's/^/  metrics-server /'
kubectl -n kube-system get pod -l component=kube-controller-manager -o jsonpath='{.items[0].spec.containers[0].command}' |
  tr ',' '\n' | grep -E "horizontal-pod-autoscaler" | sed 's/^/  controller-manager /' || true
echo "  (absent = defaults: HPA sync every 15 s, 10 % tolerance, scale-down stabilization 300 s)"
kubectl -n $NS get hpa gateway -o yaml | grep -A8 "^spec:" | sed 's/^/  /'
bash "$ROOT/v2/platform/cluster/lb-limits.sh" > /dev/null
bash "$HERE/watch.sh" gateway > "$OUT/watch.txt" 2>&1 &
watcher=$!
# the notifier scales on its queue backlog through KEDA (an HPA named keda-hpa-notifier), if set up
if kubectl -n $NS get scaledobject notifier >/dev/null 2>&1; then
  bash "$HERE/watch.sh" notifier keda-hpa-notifier > "$OUT/notifier-watch.txt" 2>&1 &
  watcher="$watcher $!"
fi
GW=http://$(kubectl -n $NS get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
t0=$(date -u +%s)
echo "== k6 start $(date -u -d @$t0 +%T); load step to $HIGH it/s at $(date -u -d @$((t0 + 30 + T1)) +%T), back to $LOW at $(date -u -d @$((t0 + 30 + T1 + 10 + T2)) +%T)"
BASE_URL=$GW STAGES=$LOW,$HIGH,$LOW STEPS=$T1,$T2,$T3 RAMP=10 WARMUP=30 MAX_VUS=600 SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" > /dev/null
sleep 30
kill $watcher 2>/dev/null; wait $watcher 2>/dev/null || true
cat "$OUT/k6.txt"
echo "== HPA and pod events (newest last)"
kubectl -n $NS get events --sort-by=.lastTimestamp \
  -o custom-columns=TIME:.lastTimestamp,KIND:.involvedObject.kind,NAME:.involvedObject.name,REASON:.reason,MSG:.message |
  grep -E "HorizontalPodAutoscaler|ScaledObject|gateway-|notifier-" | grep -vE "Unhealthy.*readyz" | tee "$OUT/events.txt" | tail -50
echo "== gateway pods: created, scheduled, containers ready, ready"
kubectl -n $NS get pods -l app.kubernetes.io/name=gateway -o json | jq -r '.items[] |
  [.metadata.name, .spec.nodeName, .metadata.creationTimestamp,
   (.status.conditions[] | select(.type == "PodScheduled") | .lastTransitionTime),
   (.status.conditions[] | select(.type == "ContainersReady") | .lastTransitionTime),
   (.status.conditions[] | select(.type == "Ready") | .lastTransitionTime)] | @tsv' | sort -k3 | tee "$OUT/pods.txt"
echo "== watcher: lines where the HPA decision or the pod set changed"
awk -F'|' '{split($2, h, " "); sig = h[2] " " h[3] $3 $4} sig != prev {print; prev = sig}' "$OUT/watch.txt" | head -80
if [ -s "$OUT/notifier-watch.txt" ]; then
  echo "== notifier watcher (KEDA): lines where the decision or the pod set changed; last field = lag per replica"
  awk -F'|' '{split($2, h, " "); sig = h[2] " " h[3] $3 $4} sig != prev {print; prev = sig}' "$OUT/notifier-watch.txt" | head -60
fi
