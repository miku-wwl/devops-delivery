#!/usr/bin/env bash
# E11 (chapter 12): the GitLab project root/platform-iac holds the OpenTofu states of v2/iac (GitLab's
# state store: one state per name, a lock that a second holder gets 409 for, versions kept). Private;
# only root. Idempotent.   bash v2/platform/iac/state-project.sh
set -euo pipefail
T=$(cat "$HOME/.lab-secrets/gitlab-root-token")
api() { curl -fsS -H "PRIVATE-TOKEN: $T" "$@"; }
GL=http://localhost:8929/api/v4
if ! api "$GL/projects/root%2Fplatform-iac" >/dev/null 2>&1; then
  api -X POST "$GL/projects" --data name=platform-iac --data visibility=private \
    --data-urlencode "description=OpenTofu state of the platform (E11, chapter 12)" >/dev/null
  echo "project root/platform-iac created"
fi
api "$GL/projects/root%2Fplatform-iac" | jq -c '{id, path_with_namespace, visibility}'
