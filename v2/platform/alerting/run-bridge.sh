#!/usr/bin/env bash
# The alert bridge outside the cluster (E9, chapter 10; platform/alerting/bridge.py). Idempotent:
#  1. GitLab project root/incidents (where alerts become issues and incidents) and a project access
#     token (Reporter, scope api) -> ~/.lab-secrets/v2/gitlab/incidents.env, never printed;
#  2. the container alert-bridge (python:3.13-slim, network kind-ent, restart unless-stopped), state
#     and event log in $ENT_STATE_DIR/alert-bridge (outside the repository and outside the cluster).
#   bash v2/platform/alerting/run-bridge.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GL=http://localhost:8929
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
S=$HOME/.lab-secrets/v2/gitlab
STATE=${ENT_STATE_DIR:-$HOME/ent-data}/alert-bridge
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
P=$(api "$GL/api/v4/projects/root%2Fincidents" 2>/dev/null | jq -r .id || true)
if [ -z "$P" ] || [ "$P" = null ]; then
  P=$(api -X POST "$GL/api/v4/projects" --data name=incidents --data visibility=private \
        --data-urlencode "description=E9: alerts and incidents of the ent platform (platform/alerting/bridge.py)" | jq -r .id)
  echo "created project root/incidents ($P)"
fi
if [ ! -s "$S/incidents.env" ]; then
  ( umask 077
    t=$(api -X POST "$GL/api/v4/projects/$P/access_tokens" --data name=alert-bridge --data "scopes[]=api" \
          --data access_level=20 --data "expires_at=$(date -d '+60 days' +%F)" | jq -r .token)
    printf 'GITLAB_TOKEN=%s\n' "$t" > "$S/incidents.env" )
  echo "created project access token alert-bridge (api, Reporter, 60 days)"
fi
mkdir -p "$STATE" && cp "$HERE/bridge.py" "$STATE/bridge.py"
docker rm -f alert-bridge >/dev/null 2>&1 || true
docker run -d --name alert-bridge --network kind-ent --restart unless-stopped \
  --env-file "$S/incidents.env" -e GITLAB_URL=http://gitlab:8929 -e GITLAB_PROJECT=root/incidents \
  -e DEADMAN_SECONDS=180 -e STATE_DIR=/state -v "$STATE:/state" python:3.13-slim python /state/bridge.py >/dev/null
for i in $(seq 1 20); do docker exec alert-bridge python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9095/healthz')" 2>/dev/null && break; sleep 1; done
echo "alert-bridge: $(docker inspect -f '{{.State.Status}} {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' alert-bridge), project root/incidents ($P)"
