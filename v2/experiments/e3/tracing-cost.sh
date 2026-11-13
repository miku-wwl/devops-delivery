#!/usr/bin/env bash
# The cost of tracing: same load (20 iterations/s, 3 min) at a given sampling ratio.
#   bash v2/experiments/e3/tracing-cost.sh <ratio> <label>
# Sets tracesSampleRatio through Git (common.yaml), waits for the rollout, lets it settle, runs
# k6 and prints per-service CPU per request and the CPU of the tracing pipeline.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RATIO=${1:?ratio}; LABEL=${2:?label}
OUT="$ROOT/v2/evidence/e3"; mkdir -p "$OUT"
sed -i -E "s/^tracesSampleRatio: \"[0-9.]+\"/tracesSampleRatio: \"$RATIO\"/" "$ROOT/v2/gitops/envs/prod/storefront/common.yaml"
TAG=$(git -C "$ROOT" log -1 --format=%h -- v2/apps/storefront)
bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" "$TAG" "tracing sample ratio $RATIO ($LABEL)"
kubectl -n argocd annotate applications -l storefront/env=prod argocd.argoproj.io/refresh=normal --overwrite >/dev/null
for i in $(seq 60); do
  v=$(kubectl -n storefront get deploy orders -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="OTEL_TRACES_SAMPLER_ARG")].value}')
  [ "$v" = "$RATIO" ] && break; sleep 5; done
for d in gateway catalog inventory payments orders notifier; do kubectl -n storefront rollout status deploy/$d --timeout=300s >/dev/null; done
echo "ratio $RATIO live on all deployments; settling 30 s"
sleep 30
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
start=$(date -u +%FT%TZ)
BASE_URL=$GW RATE=20 DURATION=3m SUMMARY="$OUT/k6-tracing-$LABEL.json" taskset -c 0-3 \
  k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" | tee "$OUT/k6-tracing-$LABEL.txt"
end=$(date -u +%FT%TZ)
s=$(date -u -d "$start + 20 seconds" +%FT%T+00:00); e=$(date -u -d "$end" +%FT%T+00:00)
python3 "$HERE/window_stats.py" "$s" "$e" --json "$OUT/window-tracing-$LABEL.json"
