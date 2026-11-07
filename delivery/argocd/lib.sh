# Shared helpers for changing the GitOps configuration repository through merge
# requests on the lab GitLab. Sourced by promote.sh, revert.sh and update-chart.sh.
# shellcheck shell=bash
GL="http://localhost:8929"
PROJECT="root%2Fdelivery-gitops"
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
WORK="$HOME/work/delivery-gitops"
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$TOKEN" | base64 -w0)"

# GitLab API call; on HTTP errors print GitLab's response body instead of hiding it.
api() { curl -sS --fail-with-body -H "PRIVATE-TOKEN: $TOKEN" "$@"; }

# Fresh clone of the configuration repository into $WORK, on a new branch.
clone_on_branch() {
  rm -rf "$WORK" && git clone -q "$GL/root/delivery-gitops.git" "$WORK"
  git -C "$WORK" checkout -q -b "$1"
}

commit_and_push() {
  git -C "$WORK" -c user.name="Lab Promoter" -c user.email="promoter@lab.local" commit -q -am "$1"
  git -C "$WORK" push -q origin HEAD 2>&1 | grep -v '^remote:' || true
}

# Create a merge request. GitLab registers pushed branches asynchronously: the
# branches API can already see the branch while merge-request creation still
# answers HTTP 400 ("source branch does not exist"), so retry for a while.
create_mr() { # <branch> <title> -> prints the MR JSON
  local branch="$1" title="$2" out=""
  for _ in $(seq 1 20); do
    if out=$(api -X POST "$GL/api/v4/projects/$PROJECT/merge_requests" \
          --data-urlencode "source_branch=$branch" --data-urlencode "target_branch=main" \
          --data-urlencode "title=$title" --data-urlencode "remove_source_branch=true" 2>&1); then
      echo "$out"; return 0
    fi
    sleep 2
  done
  echo "merge request creation failed: $out" >&2
  return 1
}

# Merge an MR once GitLab reports it mergeable; remember the merge commit for wait-sync.sh.
merge_mr() { # <iid>
  local iid="$1" merged
  for _ in $(seq 1 30); do
    [ "$(api "$GL/api/v4/projects/$PROJECT/merge_requests/$iid" | jq -r .detailed_merge_status)" = mergeable ] && break
    sleep 2
  done
  merged=$(api -X PUT "$GL/api/v4/projects/$PROJECT/merge_requests/$iid/merge")
  jq -r '"merged !\(.iid) -> main @ \(.merge_commit_sha[0:7]) by \(.merged_by.username)"' <<<"$merged"
  mkdir -p "$HOME/work"
  jq -r .merge_commit_sha <<<"$merged" > "$HOME/work/last-merge-sha"
}
