#!/usr/bin/env bash
# Install Argo CD (version pinned in automation/lab/versions.env) into the lab
# cluster and give it read access to the GitOps configuration repository.
# Idempotent.
#   bash delivery/argocd/install-argocd.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source <(tr -d '\r' < "$ROOT/automation/lab/versions.env")
SECRETS="$HOME/.lab-secrets"
REPO_URL="${GITOPS_REPO_URL:-http://gitlab:8929/root/delivery-gitops.git}"

echo "==> Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply: the Argo CD CRDs are too large for the client-side
# "last-applied-configuration" annotation.
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
for d in argocd-server argocd-repo-server argocd-applicationset-controller argocd-redis; do
  kubectl -n argocd rollout status "deploy/$d" --timeout=300s
done
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> lab setting: check Git every 60s (default 180s; production uses a Git webhook)"
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"timeout.reconciliation":"60s"}}'
kubectl -n argocd rollout restart statefulset/argocd-application-controller deploy/argocd-repo-server
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

echo "==> admin password -> $SECRETS/argocd-admin-password"
mkdir -p "$SECRETS"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' |
  base64 -d > "$SECRETS/argocd-admin-password"
chmod 600 "$SECRETS/argocd-admin-password"

echo "==> make the lab GitLab resolvable from pods as 'gitlab'"
if [ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' gitlab)" = "null" ]; then
  docker network connect kind gitlab
fi

echo "==> repository credentials (read-only project token)"
kubectl -n argocd apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-delivery-gitops
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${REPO_URL}
  username: argocd
  password: $(cat "$SECRETS/gitops-read-token")
EOF
echo "repository secret repo-delivery-gitops configured for ${REPO_URL}"
kubectl -n argocd get pods
