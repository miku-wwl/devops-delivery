#!/usr/bin/env bash
# Bootstrap the platform on the ent cluster (E1): secrets that must not live in Git, the image,
# the configuration repository, Argo CD, and the root application. Idempotent.
#   bash v2/platform/bootstrap/bootstrap.sh
# After this, every component is reconciled from root/platform-gitops by Argo CD.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2="$(cd "$HERE/../.." && pwd)"
SECRETS="$HOME/.lab-secrets/v2"
GL="http://localhost:8929"
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
kubectl config use-context kind-ent >/dev/null

echo "==> 1. generated credentials in $SECRETS (never printed, never committed)"
mkdir -p "$SECRETS" && chmod 700 "$SECRETS"
for name in pg-catalog pg-inventory pg-orders grafana-admin; do
  [ -s "$SECRETS/$name" ] || { openssl rand -hex 16 > "$SECRETS/$name"; chmod 600 "$SECRETS/$name"; }
done
for ns in data storefront monitoring argocd; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
for svc in catalog inventory orders; do
  pw="$(cat "$SECRETS/pg-$svc")"
  kubectl -n data create secret generic "pg-role-$svc" --type=kubernetes.io/basic-auth \
    --from-literal=username="$svc" --from-literal=password="$pw" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n storefront create secret generic "db-$svc" \
    --from-literal=url="postgresql://$svc:$pw@pg-main-rw.data.svc:5432/$svc" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
kubectl -n monitoring create secret generic grafana-admin --from-literal=admin-user=admin \
  --from-file=admin-password="$SECRETS/grafana-admin" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "secrets: data/pg-role-{catalog,inventory,orders}, storefront/db-{catalog,inventory,orders}, monitoring/grafana-admin"

echo "==> 2. image"
TAG="$(bash "$HERE/build-image.sh")"
echo "localhost:5001/storefront:$TAG"

echo "==> 3. configuration repository"
bash "$HERE/publish-gitops.sh" "$TAG" "bootstrap: platform and storefront $TAG"
PID=$(api "$GL/api/v4/projects/root%2Fplatform-gitops" | jq -r .id)
if [ ! -s "$SECRETS/platform-gitops-read-token" ]; then
  api -X POST "$GL/api/v4/projects/$PID/access_tokens" --data-urlencode "name=argocd-ent-read" \
    --data-urlencode "scopes[]=read_repository" --data-urlencode "access_level=20" \
    --data-urlencode "expires_at=$(date -d '+30 days' +%F)" | jq -r .token > "$SECRETS/platform-gitops-read-token"
  chmod 600 "$SECRETS/platform-gitops-read-token"
  echo "created project access token argocd-ent-read (read_repository, Reporter, 30 days)"
fi

echo "==> 4. Argo CD (helm chart argo-cd 10.14.0)"
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm upgrade --install argocd argo/argo-cd --version 10.14.0 -n argocd \
  -f "$V2/gitops/bootstrap/argocd-values.yaml" --wait --timeout 10m >/dev/null
kubectl -n argocd apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-platform-gitops
  namespace: argocd
  labels: {argocd.argoproj.io/secret-type: repository}
stringData:
  type: git
  url: http://gitlab:8929/root/platform-gitops.git
  username: argocd
  password: $(cat "$SECRETS/platform-gitops-read-token")
EOF
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null |
  base64 -d > "$SECRETS/argocd-admin-password" || true
chmod 600 "$SECRETS/argocd-admin-password"
kubectl -n argocd get pods

echo "==> 5. root application"
kubectl apply -f "$V2/gitops/bootstrap/root.yaml"
