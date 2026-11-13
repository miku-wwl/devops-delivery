#!/usr/bin/env bash
# Deployment events (E8, chapter 9): Argo CD notifications report every finished sync of the storefront
# services to GitLab's Deployments API (gitops/bootstrap/argocd-values.yaml: notifications). This gives
# the notifications controller its GitLab credential: a project access token of root/platform-gitops
# (role Developer - the lowest role that may create deployments; scope api), kept in
# ~/.lab-secrets/v2/gitlab/deployments-token and handed to the cluster as argocd-notifications-secret
# through stdin. Idempotent; bootstrap.sh runs it after installing Argo CD.
#   bash v2/platform/gitops/deploy-events.sh
set -euo pipefail
GL=http://localhost:8929
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
S=$HOME/.lab-secrets/v2/gitlab
mkdir -p "$S" && chmod 700 "$S"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
P=$(api "$GL/api/v4/projects/root%2Fplatform-gitops" | jq -r .id)
if [ ! -s "$S/deployments-token" ]; then
  ( umask 077
    api -X POST "$GL/api/v4/projects/$P/access_tokens" --data name=argocd-deployment-events \
      --data "scopes[]=api" --data access_level=30 --data "expires_at=$(date -d '+60 days' +%F)" |
      jq -r .token > "$S/deployments-token" )
  echo "created project access token argocd-deployment-events (api, Developer, 60 days)"
fi
kubectl -n argocd apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
  labels: {app.kubernetes.io/part-of: argocd}
type: Opaque
stringData:
  gitlab-deployments-token: "$(cat "$S/deployments-token")"
EOF
echo "argocd-notifications-secret applied"
