#!/usr/bin/env bash
# Install the Argo Rollouts controller (version pinned in automation/lab/versions.env).
#   bash delivery/rollouts/install-rollouts.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source <(tr -d '\r' < "$ROOT/automation/lab/versions.env")
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts --server-side --force-conflicts \
  -f "https://github.com/argoproj/argo-rollouts/releases/download/${ARGO_ROLLOUTS_VERSION}/install.yaml" >/dev/null
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=300s
kubectl argo rollouts version --short
