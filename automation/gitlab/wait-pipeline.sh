#!/usr/bin/env bash
# Wait for the latest pipeline of a ref (or a given pipeline id) on the lab GitLab
# and print its jobs. Exits 0 when the pipeline ends as success/manual-blocked.
#   bash automation/gitlab/wait-pipeline.sh main
#   bash automation/gitlab/wait-pipeline.sh --mr 1
set -euo pipefail
GL="http://localhost:8929/api/v4/projects/1"
TOKEN="$(cat ~/.lab-secrets/gitlab-root-token)"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }

if [ "${1:-}" = "--mr" ]; then
  pid=$(api "$GL/merge_requests/$2/pipelines" | jq -r '.[0].id')
else
  pid=$(api "$GL/pipelines?ref=${1:-main}&per_page=1" | jq -r '.[0].id')
fi
for _ in $(seq 1 90); do
  status=$(api "$GL/pipelines/$pid" | jq -r .status)
  case "$status" in created|waiting_for_resource|preparing|pending|running) sleep 5 ;; *) break ;; esac
done
api "$GL/pipelines/$pid" | jq -r '"pipeline #\(.id) [\(.source)] ref=\(.ref) sha=\(.sha[0:8]) status=\(.status) duration=\(.duration // "-")s"'
api "$GL/pipelines/$pid/jobs?per_page=50" |
  jq -r 'sort_by(.id)[] | "  \(.stage)\t\(.name)\t\(.status)\t\(.duration // 0 | floor)s"' | column -t -s $'\t'
[[ "$status" == success || "$status" == manual ]]
