#!/usr/bin/env bash
# E11 (chapter 12): OpenTofu for one configuration under v2/iac, with the lab's secrets.
#   bash v2/iac/tofu.sh <configuration> <tofu arguments>      e.g. bash v2/iac/tofu.sh gitlab plan
# Secrets reach OpenTofu as environment variables - never as arguments, never in a file of the
# repository: the GitLab token, the passphrase of the state encryption (created once: 32 random bytes,
# ~/.lab-secrets/v2/tofu/passphrase), the S3 key of the consumer tofu (platform/backup/object-store.sh;
# the first home of the state, read once more by the migration and by experiments/e11/state-check.sh).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG=${1:?configuration}; shift
S=$HOME/.lab-secrets/v2
umask 077; mkdir -p "$S/tofu"
[ -s "$S/tofu/passphrase" ] || openssl rand -base64 32 > "$S/tofu/passphrase"
set -a; . "$S/backup/s3-tofu.env"; set +a
TF_VAR_gitlab_token="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
TF_VAR_state_passphrase="$(cat "$S/tofu/passphrase")"
TF_VAR_s3_endpoint="http://$(docker inspect -f '{{(index .NetworkSettings.Networks "kind-ent").IPAddress}}' backup-s3):3900"
export TF_VAR_gitlab_token TF_VAR_state_passphrase TF_VAR_s3_endpoint
# the state: GitLab's state store in root/platform-iac (platform/iac/state-project.sh), one state per
# configuration; GitLab answers a second lock with 409
GL=http://localhost:8929/api/v4
PID=$(curl -fsS -H "PRIVATE-TOKEN: $TF_VAR_gitlab_token" "$GL/projects/root%2Fplatform-iac" | jq -r .id)
TF_HTTP_ADDRESS="$GL/projects/$PID/terraform/state/$CFG"
TF_HTTP_LOCK_ADDRESS="$TF_HTTP_ADDRESS/lock" TF_HTTP_UNLOCK_ADDRESS="$TF_HTTP_ADDRESS/lock"
TF_HTTP_LOCK_METHOD=POST TF_HTTP_UNLOCK_METHOD=DELETE TF_HTTP_USERNAME=root TF_HTTP_PASSWORD="$TF_VAR_gitlab_token"
export TF_HTTP_ADDRESS TF_HTTP_LOCK_ADDRESS TF_HTTP_UNLOCK_ADDRESS TF_HTTP_LOCK_METHOD TF_HTTP_UNLOCK_METHOD   TF_HTTP_USERNAME TF_HTTP_PASSWORD
export TF_IN_AUTOMATION=1 TF_INPUT=${TF_INPUT:-0}
exec tofu -chdir="$HERE/$CFG" "$@"
