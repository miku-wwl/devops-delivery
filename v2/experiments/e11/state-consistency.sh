#!/usr/bin/env bash
# E11 (chapter 12): after an interrupted state migration - which copy is where, is anything locked?
# Read-only.   bash v2/experiments/e11/state-consistency.sh
# Source: Garage (bucket tofu-state, the first home); target: GitLab's state store (root/platform-iac,
# state "gitlab"). Serial and lineage are stored in plain text next to the encrypted payload.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
T=$(cat "$HOME/.lab-secrets/gitlab-root-token")
EP="http://$(docker inspect -f '{{(index .NetworkSettings.Networks "kind-ent").IPAddress}}' backup-s3):3900/tofu-state"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
( umask 077; . "$HOME/.lab-secrets/v2/backup/s3-tofu.env"
  printf 'user = "%s:%s"\n' "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" > "$tmp/curl.cfg" )
s3() { curl -sS -K "$tmp/curl.cfg" --aws-sigv4 "aws:amz:garage:s3" "$@"; }
meta() { python3 -c 'import json,sys; d = json.load(open(sys.argv[1])); print("serial", d.get("serial"), "lineage", d.get("lineage"), "encrypted", "encrypted_data" in d)' "$1" 2>/dev/null || echo "not a state"; }

echo "== $(date -u +%T) source: Garage tofu-state/gitlab/governance.tfstate"
echo "  HTTP $(s3 -o "$tmp/src" -w '%{http_code}' "$EP/gitlab/governance.tfstate"), $(stat -c %s "$tmp/src") bytes, $(meta "$tmp/src")"
echo "  lock object: HTTP $(s3 -o /dev/null -w '%{http_code}' "$EP/gitlab/governance.tfstate.tflock")"

echo "== target: GitLab root/platform-iac, state gitlab"
PID=$(curl -fsS -H "PRIVATE-TOKEN: $T" "http://localhost:8929/api/v4/projects/root%2Fplatform-iac" | jq -r .id)
echo "  project id $PID; GET: HTTP $(curl -sS -o "$tmp/dst" -w '%{http_code}' -u "root:$T" "http://localhost:8929/api/v4/projects/$PID/terraform/state/gitlab"), $(stat -c %s "$tmp/dst") bytes, $(meta "$tmp/dst")"
curl -fsS -H "Authorization: Bearer $T" -H 'Content-Type: application/json' http://localhost:8929/api/graphql \
  -d '{"query":"{ project(fullPath: \"root/platform-iac\") { terraformStates { nodes { name lockedAt lockedByUser { username } latestVersion { serial createdAt } } } } }"}' |
  jq -c '.data.project.terraformStates.nodes[] | {name, lockedAt, lockedBy: .lockedByUser.username, serial: .latestVersion.serial, created: .latestVersion.createdAt}' | sed 's/^/  /'

echo "== the working directory and the resources in the state"
echo "  backend in .terraform/terraform.tfstate: $(jq -r .backend.type "$ROOT/v2/iac/gitlab/.terraform/terraform.tfstate")"
bash "$ROOT/v2/iac/tofu.sh" gitlab state list 2>&1 | sed 's/^/  /'
