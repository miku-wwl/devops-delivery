#!/usr/bin/env bash
# Roll back a deployment the GitOps way: revert a commit of the configuration
# repository through a merge request. Argo CD then syncs the previous state.
#   bash delivery/argocd/revert.sh <commit-sha> [--merge]
set -euo pipefail
GL="http://localhost:8929"
PROJECT="root%2Fdelivery-gitops"
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
sha="${1:?usage: revert.sh <commit-sha> [--merge]}"; merge="${2:-}"

work="$HOME/work/delivery-gitops"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$TOKEN" | base64 -w0)"
rm -rf "$work" && git clone -q "$GL/root/delivery-gitops.git" "$work"
cd "$work"
branch="revert/${sha:0:7}-$(date +%H%M%S)"
git checkout -q -b "$branch"
# merge commits need -m 1: "keep the first parent (main) as the mainline"
parents=$(git rev-list --parents -n 1 "$sha" | wc -w)
if [ "$parents" -gt 2 ]; then mainline=(-m 1); else mainline=(); fi
git -c user.name="Lab Promoter" -c user.email="promoter@lab.local" revert --no-edit "${mainline[@]}" "$sha" >/dev/null
git show --stat --format='%h %s' HEAD | head -4
git push -q origin "$branch" 2>&1 | grep -v '^remote:' || true
enc="${branch//\//%2F}"
for _ in $(seq 1 30); do api "$GL/api/v4/projects/$PROJECT/repository/branches/$enc" >/dev/null 2>&1 && break; sleep 1; done
mr=$(api -X POST "$GL/api/v4/projects/$PROJECT/merge_requests" \
  --data-urlencode "source_branch=$branch" --data-urlencode "target_branch=main" \
  --data-urlencode "title=Revert ${sha:0:7}" --data-urlencode "remove_source_branch=true")
iid=$(jq -r .iid <<<"$mr")
echo "merge request !${iid}: $(jq -r .web_url <<<"$mr")"
if [ "$merge" = "--merge" ]; then
  for _ in $(seq 1 20); do
    [ "$(api "$GL/api/v4/projects/$PROJECT/merge_requests/$iid" | jq -r .detailed_merge_status)" = mergeable ] && break; sleep 2
  done
  merged=$(api -X PUT "$GL/api/v4/projects/$PROJECT/merge_requests/$iid/merge")
  jq -r '"merged !\(.iid) -> main @ \(.merge_commit_sha[0:7])"' <<<"$merged"
  jq -r .merge_commit_sha <<<"$merged" > "$HOME/work/last-merge-sha"
fi
