#!/usr/bin/env bash
# Create the GitOps configuration repository on the lab GitLab, push its seed
# content once, and create a read-only project access token for Argo CD.
# Idempotent. Secrets go to ~/.lab-secrets/ and are never printed.
#   bash delivery/argocd/seed-gitops-repo.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GL="http://localhost:8929"
SECRETS="$HOME/.lab-secrets"
TOKEN="$(cat "$SECRETS/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }

# 1. project
if ! api "$GL/api/v4/projects/root%2Fdelivery-gitops" >/dev/null 2>&1; then
  api -X POST "$GL/api/v4/projects" \
    --data-urlencode "name=delivery-gitops" \
    --data-urlencode "visibility=private" \
    --data-urlencode "initialize_with_readme=false" \
    --data-urlencode "remove_source_branch_after_merge=true" | jq -c '{id, path_with_namespace}'
fi
PID=$(api "$GL/api/v4/projects/root%2Fdelivery-gitops" | jq -r .id)

# 2. seed commit, only while the repository is still empty
if [ "$(api "$GL/api/v4/projects/$PID" | jq -r .empty_repo)" = "true" ]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  cp -r "$ROOT/delivery/gitops/." "$work/"
  mkdir -p "$work/charts"
  cp -r "$ROOT/delivery/helm/demo-api" "$work/charts/"
  git -C "$work" init -q -b main
  git -C "$work" add -A
  git -C "$work" -c user.name="Lab Seeder" -c user.email="seeder@lab.local" \
    commit -q -m "seed: demo-api chart, environment values and Argo CD apps"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
    GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$TOKEN" | base64 -w0)"
  git -C "$work" push -q "$GL/root/delivery-gitops.git" main
  echo "seeded root/delivery-gitops"
fi

# 3. read-only token for Argo CD (Reporter role, read_repository scope only)
if [ ! -s "$SECRETS/gitops-read-token" ]; then
  api -X POST "$GL/api/v4/projects/$PID/access_tokens" \
    --data-urlencode "name=argocd-read" \
    --data-urlencode "scopes[]=read_repository" \
    --data-urlencode "access_level=20" \
    --data-urlencode "expires_at=$(date -d '+30 days' +%F)" | jq -r .token > "$SECRETS/gitops-read-token"
  chmod 600 "$SECRETS/gitops-read-token"
  echo "created project access token argocd-read (read_repository, Reporter)"
fi

api "$GL/api/v4/projects/$PID/repository/tree?recursive=true&per_page=100" |
  jq -r '.[] | select(.type == "blob") | .path'
