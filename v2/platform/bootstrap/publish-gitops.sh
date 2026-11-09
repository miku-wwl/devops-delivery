#!/usr/bin/env bash
# Publish v2/gitops to the configuration repository root/platform-gitops on the lab GitLab.
#   bash v2/platform/bootstrap/publish-gitops.sh <image-tag> "<commit message>"
# The repository on GitLab is what Argo CD reads; v2/gitops in this GitHub repository is its
# reviewed source. IMAGE_TAG placeholders are replaced with the built image tag. From E8 on,
# changes go through merge requests instead (platform/gitops/*.sh).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2="$(cd "$HERE/../.." && pwd)"
TAG="${1:?usage: publish-gitops.sh <image-tag> <message>}"
MSG="${2:-publish from v2/gitops}"
GL="http://localhost:8929"
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$TOKEN" | base64 -w0)"

if ! api "$GL/api/v4/projects/root%2Fplatform-gitops" >/dev/null 2>&1; then
  api -X POST "$GL/api/v4/projects" --data-urlencode "name=platform-gitops" \
    --data-urlencode "visibility=private" --data-urlencode "initialize_with_readme=false" \
    --data-urlencode "default_branch=main" | jq -c '{id, path_with_namespace}'
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ "$(api "$GL/api/v4/projects/root%2Fplatform-gitops" | jq -r .empty_repo)" = "true" ]; then
  git -C "$work" init -q -b main
else
  git clone -q "$GL/root/platform-gitops.git" "$work"
fi
# mirror v2/gitops exactly (deleted files are deleted), keep .git
find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -r "$V2/gitops/." "$work/"
grep -rl 'IMAGE_TAG' "$work/envs" "$work/tenants" | xargs -r sed -i "s/IMAGE_TAG/$TAG/g"   # tenants/: E5
git -C "$work" add -A
if git -C "$work" diff --cached --quiet; then
  echo "platform-gitops: no changes"
else
  git -C "$work" -c user.name="Platform Publisher" -c user.email="publisher@lab.local" commit -q -m "$MSG"
  git -C "$work" push -q "$GL/root/platform-gitops.git" HEAD:main
  echo "platform-gitops: pushed $(git -C "$work" rev-parse --short HEAD) ($MSG)"
fi
