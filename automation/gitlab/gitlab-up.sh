#!/usr/bin/env bash
# Start the local GitLab lab and wire it up end to end (idempotent).
#   bash automation/gitlab/gitlab-up.sh
#
# 1. generate the root password (~/.lab-secrets/gitlab-root-password, mode 600)
# 2. docker compose up, wait until GitLab answers /-/readiness
# 3. create a root personal access token via gitlab-rails (~/.lab-secrets/gitlab-root-token)
# 4. create project root/devops-delivery ("pipelines must succeed" before merge)
# 5. create an instance runner (authentication-token flow) and register the
#    Docker executor on the compose network
# Secrets are never printed and never written inside the repository.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="$HOME/.lab-secrets"
GL_URL="http://localhost:8929"
NETWORK="gitlab-lab_default"
mkdir -p "$SECRETS" && chmod 700 "$SECRETS"

if [ ! -s "$SECRETS/gitlab-root-password" ]; then
  # 24 random alphanumerics. (Not "tr </dev/urandom | head": under "set -o pipefail"
  # tr dies of SIGPIPE when head exits, and "set -e" silently aborts the script.)
  python3 -c 'import secrets, string; a = string.ascii_letters + string.digits; print("".join(secrets.choice(a) for _ in range(24)), end="")' \
    > "$SECRETS/gitlab-root-password"
  chmod 600 "$SECRETS/gitlab-root-password"
fi
GITLAB_ROOT_PASSWORD="$(cat "$SECRETS/gitlab-root-password")"
export GITLAB_ROOT_PASSWORD

echo "==> docker compose up"
docker compose -f "$HERE/compose.yaml" up -d --quiet-pull

echo "==> waiting for GitLab (first boot takes several minutes)"
# Not /-/readiness: GitLab answers health endpoints only for IPs in its monitoring
# allowlist (loopback by default); through the Docker port mapping we get a 404.
# Use the container's own healthcheck plus the sign-in page instead.
code=""
for i in $(seq 1 120); do
  health=$(docker inspect -f '{{.State.Health.Status}}' gitlab 2>/dev/null || true)
  code=$(curl -s -o /dev/null -w '%{http_code}' "$GL_URL/users/sign_in" || true)
  if [ "$health" = "healthy" ] && [ "$code" = "200" ]; then echo "ready (container healthy, sign-in page 200)"; break; fi
  sleep 10
done
[ "$code" = "200" ] || { echo "GitLab did not become ready" >&2; exit 1; }

if [ ! -s "$SECRETS/gitlab-root-token" ]; then
  echo "==> creating root personal access token (gitlab-rails runner)"
  docker exec gitlab gitlab-rails runner "
    user = User.find_by_username('root')
    token = user.personal_access_tokens.create!(
      name: 'lab-automation',
      scopes: [:api, :read_repository, :write_repository],
      expires_at: 30.days.from_now)
    puts token.token" | tail -1 > "$SECRETS/gitlab-root-token"
  chmod 600 "$SECRETS/gitlab-root-token"
fi
GL_TOKEN="$(cat "$SECRETS/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $GL_TOKEN" "$@"; }
echo "token check: user=$(api "$GL_URL/api/v4/user" | jq -r .username)"

echo "==> project root/devops-delivery"
if ! api "$GL_URL/api/v4/projects/root%2Fdevops-delivery" >/dev/null 2>&1; then
  api -X POST "$GL_URL/api/v4/projects" \
    --data-urlencode "name=devops-delivery" \
    --data-urlencode "visibility=private" \
    --data-urlencode "only_allow_merge_if_pipeline_succeeds=true" \
    --data-urlencode "remove_source_branch_after_merge=true" \
    --data-urlencode "initialize_with_readme=false" | jq '{id, path_with_namespace, only_allow_merge_if_pipeline_succeeds}'
fi

echo "==> runner"
if ! docker exec gitlab-runner grep -q '^\[\[runners\]\]' /etc/gitlab-runner/config.toml 2>/dev/null; then
  RUNNER_TOKEN=$(api -X POST "$GL_URL/api/v4/user/runners" \
    --data-urlencode "runner_type=instance_type" \
    --data-urlencode "description=lab-docker-runner" \
    --data-urlencode "run_untagged=true" | jq -r .token)
  docker exec gitlab-runner gitlab-runner register --non-interactive \
    --url "http://gitlab:8929" --clone-url "http://gitlab:8929" \
    --token "$RUNNER_TOKEN" \
    --executor docker --docker-image "alpine:3.22" \
    --docker-network-mode "$NETWORK" \
    --docker-volumes /var/run/docker.sock:/var/run/docker.sock >/dev/null
  # Let lint and test run in parallel.
  docker exec gitlab-runner sed -i 's/^concurrent = .*/concurrent = 4/' /etc/gitlab-runner/config.toml
fi
# gitlab-runner colours its output: "Token\e[0;m=glrt-..." - strip ANSI codes FIRST,
# otherwise a plain "Token=" pattern never matches and the token leaks into logs.
docker exec gitlab-runner gitlab-runner list 2>&1 |
  sed -E 's/\x1b\[[0-9;]*m//g; s/(Token=)[^ ]+/\1<redacted>/; s/glrt-[A-Za-z0-9._-]+/<redacted>/g'
echo "GitLab lab ready: $GL_URL  (user root, password in $SECRETS/gitlab-root-password)"
