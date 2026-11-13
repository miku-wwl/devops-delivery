#!/usr/bin/env bash
# E11: the governance of root/platform-gitops as GitLab reports it (sorted JSON; no tokens).
#   bash v2/experiments/e11/gitlab-snapshot.sh > <file>
set -euo pipefail
T=$(cat "$HOME/.lab-secrets/gitlab-root-token")
api() { curl -fsS -H "PRIVATE-TOKEN: $T" "http://localhost:8929/api/v4/$1"; }
jq -S -n --argjson p "$(api 'projects/root%2Fplatform-gitops')" \
  --argjson b "$(api 'projects/root%2Fplatform-gitops/protected_branches/main')" \
  --argjson m "$(api 'projects/root%2Fplatform-gitops/members')" '{
  project: ($p | {id, path_with_namespace, visibility, default_branch, only_allow_merge_if_pipeline_succeeds,
                  allow_merge_on_skipped_pipeline, remove_source_branch_after_merge}),
  protected_main: ($b | {allow_force_push, push: [.push_access_levels[].access_level], merge: [.merge_access_levels[].access_level]}),
  members: ($m | map({username, access_level}) | sort_by(.username))}'
