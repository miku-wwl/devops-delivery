#!/usr/bin/env bash
# Ship a new version of the Helm chart to the GitOps configuration repository
# (charts/demo-api) through a merge request. The chart in delivery/helm is the
# source; the config repository holds the copy that is actually deployed.
#   bash delivery/argocd/update-chart.sh [--merge]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/delivery/argocd/lib.sh"

version="$(yq -r .version "$ROOT/delivery/helm/demo-api/Chart.yaml")"
branch="chart/demo-api-${version}-$(date +%H%M%S)"
clone_on_branch "$branch"
rm -rf "$WORK/charts/demo-api" && cp -r "$ROOT/delivery/helm/demo-api" "$WORK/charts/demo-api"
git -C "$WORK" add -A charts/demo-api
git -C "$WORK" diff --cached --stat | tail -1
commit_and_push "chart: demo-api ${version}"
mr=$(create_mr "$branch" "chart: demo-api ${version}")
iid=$(jq -r .iid <<<"$mr")
echo "merge request !${iid}: $(jq -r .web_url <<<"$mr")"
if [ "${1:-}" = "--merge" ]; then merge_mr "$iid"; fi
