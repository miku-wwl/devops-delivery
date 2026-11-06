#!/usr/bin/env bash
# Change the desired state of an environment through a merge request in the
# GitOps configuration repository - the only way deployments happen in this lab.
#
#   bash delivery/argocd/promote.sh <env> <key=value | key:=raw> ... [--merge] [--title "..."]
#
#   bash delivery/argocd/promote.sh prod image.tag=0.1.1 --merge
#   bash delivery/argocd/promote.sh prod image.digest=sha256:... --merge
#   bash delivery/argocd/promote.sh prod faults.errorRate:=0.5 --merge --title "tune retries"
#
# key=value sets a YAML string; key:=raw sets a raw YAML value (numbers, booleans).
# Prints the merge request and, with --merge, the merge commit Argo CD will sync.
set -euo pipefail
GL="http://localhost:8929"
PROJECT="root%2Fdelivery-gitops"
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }

env="${1:?usage: promote.sh <env> key=value ... [--merge] [--title text]}"; shift
merge=false; title=""; changes=()
while [ $# -gt 0 ]; do
  case "$1" in
    --merge) merge=true ;;
    --title) title="$2"; shift ;;
    *) changes+=("$1") ;;
  esac
  shift
done
[ ${#changes[@]} -gt 0 ] || { echo "no changes given" >&2; exit 2; }

work="$HOME/work/delivery-gitops"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$TOKEN" | base64 -w0)"
rm -rf "$work" && git clone -q "$GL/root/delivery-gitops.git" "$work"
cd "$work"
branch="change/${env}-$(date +%Y%m%d%H%M%S)"
git checkout -q -b "$branch"

file="envs/${env}/values.yaml"
[ -f "$file" ] || { echo "unknown environment: $env" >&2; exit 2; }
for c in "${changes[@]}"; do
  if [[ "$c" == *":="* ]]; then
    key="${c%%:=*}" val="${c#*:=}"; yq -i ".${key} = ${val}" "$file"
  else
    key="${c%%=*}" val="${c#*=}"; yq -i ".${key} = \"${val}\"" "$file"
  fi
done
git diff --stat
git diff -U1 -- "$file" | sed -n '5,$p'
summary="${env}: ${changes[*]}"
git -c user.name="Lab Promoter" -c user.email="promoter@lab.local" commit -q -am "deploy(${summary})"
git push -q origin "$branch" 2>&1 | grep -v '^remote:' || true

# GitLab registers a pushed branch asynchronously (post-receive background job);
# creating the MR immediately can fail with HTTP 400, so wait until it is visible.
enc_branch="${branch//\//%2F}"
for _ in $(seq 1 30); do
  api "$GL/api/v4/projects/$PROJECT/repository/branches/$enc_branch" >/dev/null 2>&1 && break
  sleep 1
done

mr=$(api -X POST "$GL/api/v4/projects/$PROJECT/merge_requests" \
  --data-urlencode "source_branch=$branch" --data-urlencode "target_branch=main" \
  --data-urlencode "title=${title:-deploy(${summary})}" \
  --data-urlencode "remove_source_branch=true")
iid=$(jq -r .iid <<<"$mr")
echo "merge request !${iid}: $(jq -r .web_url <<<"$mr")"

if $merge; then
  for _ in $(seq 1 20); do
    s=$(api "$GL/api/v4/projects/$PROJECT/merge_requests/$iid" | jq -r .detailed_merge_status)
    [ "$s" = mergeable ] && break; sleep 2
  done
  merged=$(api -X PUT "$GL/api/v4/projects/$PROJECT/merge_requests/$iid/merge")
  jq -r '"merged !\(.iid) -> main @ \(.merge_commit_sha[0:7]) by \(.merged_by.username)"' <<<"$merged"
  # remembered for wait-sync.sh
  jq -r .merge_commit_sha <<<"$merged" > "$HOME/work/last-merge-sha"
fi
