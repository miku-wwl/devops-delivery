#!/usr/bin/env bash
# Capacity after losing a replica: the gateway with one pod instead of two, through GitOps.
#   bash v2/experiments/e3/one-replica.sh <label> <rate>[,<rate> ...]
# Publishes replicas: 1 for the gateway to the GitOps repository (Argo CD self-heals, so a
# kubectl scale would be undone within seconds), waits until one gateway pod is left, runs the
# step load (step-ramp.sh), and always publishes replicas: 2 again. The GitOps history keeps
# both changes. The local file is restored as well; only the published repository saw "1".
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; RATES=${2:?rates}
VALUES="$ROOT/v2/gitops/envs/prod/storefront/services/gateway.yaml"
TAG=$(kubectl -n storefront get deploy gateway -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
pods() { kubectl -n storefront get pods -l app.kubernetes.io/name=gateway --no-headers 2>/dev/null | grep -c Running || true; }
publish() {   # <replicas> <message>
  sed -i "s/^replicas: .*/replicas: $1/" "$VALUES"
  bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" "$TAG" "$2"
  kubectl -n argocd annotate application storefront-gateway-prod argocd.argoproj.io/refresh=normal --overwrite > /dev/null
  for i in $(seq 1 60); do
    [ "$(kubectl -n storefront get deploy gateway -o jsonpath='{.spec.replicas}')" = "$1" ] && break; sleep 5
  done
  kubectl -n storefront rollout status deploy/gateway --timeout=300s
  for i in $(seq 1 60); do [ "$(pods)" = "$1" ] && break; sleep 5; done
  echo "gateway pods running: $(pods)"
}
trap 'publish 2 "E3: gateway back to 2 replicas"; git -C "$ROOT" checkout -- "$VALUES"' EXIT
publish 1 "E3: gateway 1 replica (capacity after losing a replica, chapter 4)"
sleep 30
OUT="$ROOT/v2/evidence/e3/steps-$LABEL"; mkdir -p "$OUT"
n=$(tr ',' '
' <<<"$RATES" | wc -l)
# the one gateway pod's main thread: CPU and run-queue time every 10 s, for the whole step load
bash "$HERE/sched-sample.sh" gateway $(( ${WARMUP:-30} + n * ${STEP:-120} + (n - 1) * ${RAMP:-10} + 30 )) 10   > "$OUT/sched.txt" 2>&1 &
sampler=$!
bash "$HERE/step-ramp.sh" "$LABEL" "$RATES"
wait "$sampler" || true
bash "$HERE/where-waits.sh" "$LABEL"
