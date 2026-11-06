#!/usr/bin/env bash
# Synthetic pre-release gate (roadmap D9): deploy a candidate demo-api into a throwaway
# namespace of the current Kubernetes context, run the k6 synthetic API test against it,
# tear everything down, and exit with k6's status (0 = pass, 99 = a threshold failed).
#
#   synthetic/run-gate.sh --image demo-api --tag candidate                 # kind-loaded image (CI)
#   synthetic/run-gate.sh --image ghcr.io/<owner>/<repo>/demo-api --digest sha256:...  # lab
#   ... --fault latency|errors     inject a fault through the chart values (drills)
#   ... --summary-dir out          where k6-summary.{json,md} are written
#   ... --keep                     leave the namespace in place for debugging
#
# Requires kubectl, helm and k6 on PATH and a cluster that can pull the image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="" TAG="" DIGEST="" FAULT="none" KEEP=0 SUMMARY_DIR="${ROOT}/out"
NS="synthetic-$(date +%s)"
PORT="${PORT:-18080}"
RELEASE="demo-api-gate"

while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --digest) DIGEST="$2"; shift 2 ;;
    --fault) FAULT="$2"; shift 2 ;;
    --namespace) NS="$2"; shift 2 ;;
    --summary-dir) SUMMARY_DIR="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$IMAGE" ] || { echo "--image is required" >&2; exit 2; }
[ -n "$TAG$DIGEST" ] || { echo "--tag or --digest is required" >&2; exit 2; }

case "$FAULT" in
  none) FAULT_ARGS=() ;;
  latency) FAULT_ARGS=(--set-json 'faults.latencyMs=600') ;;   # slow pricing dependency
  errors) FAULT_ARGS=(--set-json 'faults.errorRate=0.2') ;;     # 20% of API calls fail
  *) echo "--fault must be none, latency or errors" >&2; exit 2 ;;
esac
if [ -n "$DIGEST" ]; then IMAGE_ARGS=(--set "image.repository=$IMAGE" --set "image.digest=$DIGEST")
else IMAGE_ARGS=(--set "image.repository=$IMAGE" --set "image.tag=$TAG"); fi

PF_PID=""
cleanup() {
  [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true
  if [ "$KEEP" -eq 0 ]; then
    helm uninstall "$RELEASE" -n "$NS" >/dev/null 2>&1 || true
    kubectl delete namespace "$NS" --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> candidate ${IMAGE}${DIGEST:+@$DIGEST}${TAG:+:$TAG}  fault=${FAULT}  namespace=${NS}"
kubectl create namespace "$NS" >/dev/null
kubectl label namespace "$NS" purpose=synthetic-gate \
  pod-security.kubernetes.io/enforce=restricted >/dev/null

helm upgrade --install "$RELEASE" "$ROOT/delivery/helm/demo-api" -n "$NS" \
  "${IMAGE_ARGS[@]}" --set environment=staging --set metricsAnnotations=false \
  "${FAULT_ARGS[@]}" --wait --timeout 3m >/dev/null
kubectl -n "$NS" get pods -o wide --no-headers

kubectl -n "$NS" port-forward "svc/$RELEASE" "${PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
for _ in $(seq 1 30); do curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://127.0.0.1:${PORT}/api/v1/info"; echo

mkdir -p "$SUMMARY_DIR"
set +e
k6 run --quiet -e "BASE_URL=http://127.0.0.1:${PORT}" -e "SUMMARY_DIR=${SUMMARY_DIR}" \
  "$ROOT/synthetic/k6/api-check.js"
rc=$?
set -e
if [ "$rc" -eq 0 ]; then echo "==> synthetic gate PASSED"; else echo "==> synthetic gate FAILED (k6 exit $rc)"; fi
exit "$rc"
