#!/usr/bin/env bash
# Changes to the configuration repository root/platform-gitops go through merge requests (E8,
# chapter 9; the project is gated by platform/gitops/setup.sh).
#   bash v2/platform/gitops/mr.sh propose <image-tag> "<title>" [--as alice|root] [--edit '<shell>']
#       mirrors v2/gitops into a new branch (IMAGE_TAG replaced, as publish-gitops.sh does), opens a
#       merge request and waits for its pipeline; prints "MR !<iid> ... pipeline <id>: <status>" and,
#       if a job failed, the policy results from its log. Exit 0 only when the pipeline succeeded.
#       --edit runs a shell command in the clone before the commit (drills: a deliberate violation).
#   bash v2/platform/gitops/mr.sh merge <iid>     # as a Maintainer (root); GitLab itself refuses a
#                                                  # merge request whose pipeline did not succeed
#   bash v2/platform/gitops/mr.sh close <iid>
# Tokens come from ~/.lab-secrets and travel in an HTTP header (environment), never as arguments.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2="$(cd "$HERE/../.." && pwd)"
GL=http://localhost:8929 P=root%2Fplatform-gitops
ROOT_TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOK" "$@"; }
TOK=$ROOT_TOKEN
cmd=${1:?propose|merge|close}; shift
case $cmd in
propose)
  TAG=${1:?image tag}; TITLE=${2:?title}; shift 2; AS=root EDIT=
  while [ $# -gt 0 ]; do
    case $1 in --as) AS=$2; shift 2 ;; --edit) EDIT=$2; shift 2 ;; *) echo "unknown option $1" >&2; exit 2 ;; esac
  done
  if [ "$AS" = root ]; then NAME="Platform Publisher" MAIL=publisher@lab.local
  else TOK="$(cat "$HOME/.lab-secrets/v2/gitlab/$AS-token")"; NAME="$AS" MAIL="$AS@lab.local"; fi
  work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
  export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
    GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$TOK" | base64 -w0)"
  git clone -q "$GL/root/platform-gitops.git" "$work"
  branch="mr/$(date -u +%Y%m%d-%H%M%S)-$AS"
  git -C "$work" checkout -q -b "$branch"
  find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  cp -r "$V2/gitops/." "$work/"
  grep -rl 'IMAGE_TAG' "$work/envs" "$work/tenants" | xargs -r sed -i "s/IMAGE_TAG/$TAG/g"
  if [ -n "$EDIT" ]; then (cd "$work" && sh -c "$EDIT"); fi
  git -C "$work" add -A
  if git -C "$work" diff --cached --quiet; then echo "no changes against main"; exit 3; fi
  git -C "$work" -c user.name="$NAME" -c user.email="$MAIL" commit -q -m "$TITLE"
  git -C "$work" push -q origin "$branch" 2>&1 | grep -v "^remote:" || true
  iid=$(api -X POST "$GL/api/v4/projects/$P/merge_requests" --data-urlencode "source_branch=$branch" \
          --data target_branch=main --data-urlencode "title=$TITLE" --data remove_source_branch=true | jq -r .iid)
  TOK=$ROOT_TOKEN
  t0=$(date +%s)
  for i in $(seq 1 180); do
    mr=$(api "$GL/api/v4/projects/$P/merge_requests/$iid")
    st=$(jq -r '.head_pipeline.status // "none"' <<<"$mr")
    case $st in success|failed|canceled|skipped) break ;; esac
    sleep 5
  done
  pid=$(jq -r '.head_pipeline.id // empty' <<<"$mr")
  echo "MR !$iid ($branch, by $AS) pipeline $pid: $st after $(( $(date +%s) - t0 )) s; diff: $(api "$GL/api/v4/projects/$P/merge_requests/$iid/changes" | jq -r '[.changes[].new_path] | join(" ")')"
  if [ "$st" != success ] && [ -n "$pid" ]; then
    for job in $(api "$GL/api/v4/projects/$P/pipelines/$pid/jobs" | jq -r '.[] | select(.status == "failed") | .id'); do
      echo "  failed job $job:"
      api "$GL/api/v4/projects/$P/jobs/$job/trace" | grep -E "failed|validation error|^pass:|Error" | sed 's/^/    /' | head -12
    done
  fi
  [ "$st" = success ]
  ;;
merge)
  iid=${1:?iid}
  out=$(curl -sS -w '\n%{http_code}' -X PUT -H "PRIVATE-TOKEN: $TOK" "$GL/api/v4/projects/$P/merge_requests/$iid/merge")
  code=$(tail -1 <<<"$out")
  echo "merge !$iid as root (Maintainer): HTTP $code $(head -n -1 <<<"$out" | jq -r '.state // .message // .' 2>/dev/null | head -1)"
  [ "$code" = 200 ]
  ;;
close)
  api -X PUT "$GL/api/v4/projects/$P/merge_requests/${1:?iid}" --data state_event=close | jq -r '"MR !\(.iid): \(.state)"'
  ;;
*) echo "unknown command $cmd" >&2; exit 2 ;;
esac
