#!/usr/bin/env bash
# Roll back a deployment the GitOps way: revert a commit of the configuration
# repository through a merge request. Argo CD then syncs the previous state.
#   bash delivery/argocd/revert.sh <commit-sha> [--merge]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
sha="${1:?usage: revert.sh <commit-sha> [--merge]}"; merge="${2:-}"

branch="revert/${sha:0:7}-$(date +%H%M%S)"
clone_on_branch "$branch"
# merge commits need -m 1: "keep the first parent (main) as the mainline"
if [ "$(git -C "$WORK" rev-list --parents -n 1 "$sha" | wc -w)" -gt 2 ]; then mainline=(-m 1); else mainline=(); fi
git -C "$WORK" -c user.name="Lab Promoter" -c user.email="promoter@lab.local" \
  revert --no-edit "${mainline[@]}" "$sha" >/dev/null
git -C "$WORK" show --stat --format='%h %s' HEAD | head -4
git -C "$WORK" push -q origin HEAD 2>&1 | grep -v '^remote:' || true
mr=$(create_mr "$branch" "Revert ${sha:0:7}")
iid=$(jq -r .iid <<<"$mr")
echo "merge request !${iid}: $(jq -r .web_url <<<"$mr")"
if [ "$merge" = "--merge" ]; then merge_mr "$iid"; fi
