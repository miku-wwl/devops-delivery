#!/usr/bin/env bash
# E8 (chapter 9): make the configuration repository root/platform-gitops a gated repository.
#  - a merge request merges only when its pipeline succeeded (.gitlab-ci.yml: render + release
#    policies), not when the pipeline was skipped;
#  - main is protected: nobody pushes to it, Maintainers merge - changes reach main only through a
#    merge request, the publisher's included (platform/gitops/mr.sh);
#  - a developer account "alice" (team shop), role Developer: she pushes branches and opens merge
#    requests, she cannot change main. Her impersonation token (api, write_repository, 30 days) goes
#    to ~/.lab-secrets/v2/gitlab/alice-token (mode 600). The account's password is random, goes in
#    through stdin and is not kept: nobody signs in with it.
# Idempotent.
#   bash v2/platform/gitops/setup.sh
set -euo pipefail
GL=http://localhost:8929
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
S=$HOME/.lab-secrets/v2/gitlab
umask 077; mkdir -p "$S"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
P=$(api "$GL/api/v4/projects/root%2Fplatform-gitops" | jq -r .id)

api -X PUT "$GL/api/v4/projects/$P" --data only_allow_merge_if_pipeline_succeeds=true \
  --data allow_merge_on_skipped_pipeline=false --data remove_source_branch_after_merge=true >/dev/null
# main: push = no one (0), merge = Maintainers (40), no force push
api -X DELETE "$GL/api/v4/projects/$P/protected_branches/main" >/dev/null 2>&1 || true
api -X POST "$GL/api/v4/projects/$P/protected_branches" --data name=main --data push_access_level=0 \
  --data merge_access_level=40 --data allow_force_push=false >/dev/null

U=$(api "$GL/api/v4/users?username=alice" | jq -r '.[0].id // empty')
if [ -z "$U" ]; then
  U=$(openssl rand -base64 24 | api -X POST "$GL/api/v4/users" --data username=alice \
        --data-urlencode "name=Alice (team shop)" --data email=alice@lab.local \
        --data-urlencode "password@-" --data skip_confirmation=true | jq -r .id)
  echo "user alice created ($U)"
fi
api -X POST "$GL/api/v4/projects/$P/members" --data "user_id=$U" --data access_level=30 >/dev/null 2>&1 ||
  api -X PUT "$GL/api/v4/projects/$P/members/$U" --data access_level=30 >/dev/null
if [ ! -s "$S/alice-token" ]; then
  api -X POST "$GL/api/v4/users/$U/impersonation_tokens" --data name=e8-merge-requests \
    --data "scopes[]=api" --data "scopes[]=write_repository" --data "expires_at=$(date -d '+30 days' +%F)" |
    jq -r .token > "$S/alice-token"
  echo "impersonation token for alice -> $S/alice-token"
fi
api "$GL/api/v4/projects/$P" | jq -c '{project: .path_with_namespace, only_allow_merge_if_pipeline_succeeds, allow_merge_on_skipped_pipeline}'
api "$GL/api/v4/projects/$P/protected_branches/main" | jq -c '{branch: .name, push: [.push_access_levels[].access_level_description], merge: [.merge_access_levels[].access_level_description]}'
api "$GL/api/v4/projects/$P/members/$U" | jq -c '{member: .username, access_level}'
