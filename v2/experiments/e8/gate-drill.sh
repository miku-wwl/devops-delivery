#!/usr/bin/env bash
# The merge-request gate drill (E8, chapter 9): alice (team shop, Developer) proposes four changes to
# the catalog's production release, three of them against a release policy; then a direct push to
# main. Expected results: evidence/e8/gate-prediction.md. Output: evidence/e8/gate-drill.log.
#   bash v2/experiments/e8/gate-drill.sh [all|g5]     # g5: only the compliant change and the direct push
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MR="$ROOT/v2/platform/gitops/mr.sh"
GL=http://localhost:8929 P=root%2Fplatform-gitops
RT="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
AT="$(cat "$HOME/.lab-secrets/v2/gitlab/alice-token")"
TAG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')
F=envs/prod/storefront/services/catalog.yaml
now() { date -u +%T; }
main_sha() { curl -fsS -H "PRIVATE-TOKEN: $RT" "$GL/api/v4/projects/$P/repository/branches/main" | jq -r .commit.short_id; }
cluster() { kubectl -n storefront get deploy catalog -o json | jq -r '"catalog in the cluster: image \(.spec.template.spec.containers[0].image | sub(".*/"; "")), replicas \(.spec.replicas), memory limit \(.spec.template.spec.containers[0].resources.limits.memory // "none"), DB_POOL_MAX \([.spec.template.spec.containers[0].env[] | select(.name == "DB_POOL_MAX") | .value][0])"'; }
case_() { # name edit
  echo; echo "== $(now) $1"
  out=$(bash "$MR" propose "$TAG" "$1" --as alice --edit "$2" 2>&1); rc=$?
  echo "$out"
  iid=$(sed -n 's/^MR !\([0-9]*\).*/\1/p' <<<"$out")
  if [ "$rc" != 0 ] && [ -n "$iid" ]; then
    bash "$MR" merge "$iid"
    bash "$MR" close "$iid"
  fi
  echo "   main: $(main_sha); $(cluster)"
}
echo "== $(now) before: main $(main_sha); $(cluster)"
if [ "${1:-all}" = all ]; then
case_ "G2 catalog: image tag latest" "printf 'image: {tag: latest}\n' >> $F"
case_ "G3 catalog: no memory limit" "printf 'resources: {limits: {memory: null}}\n' >> $F"
case_ "G4 catalog: one replica in production" "sed -i 's/^replicas: 2$/replicas: 1/' $F"
fi

echo; echo "== $(now) G5 catalog: database pool 10 -> 12 (compliant)"
out=$(bash "$MR" propose "$TAG" "G5 catalog: database pool 10 -> 12" --as alice --edit "sed -i 's/DB_POOL_MAX: \"10\"/DB_POOL_MAX: \"12\"/' $F" 2>&1)
echo "$out"
iid=$(sed -n 's/^MR !\([0-9]*\).*/\1/p' <<<"$out")
code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H "PRIVATE-TOKEN: $AT" "$GL/api/v4/projects/$P/merge_requests/$iid/merge")
echo "merge !$iid as alice (Developer): HTTP $code"
if ! bash "$MR" merge "$iid"; then echo "   not merged; main $(main_sha)"; exit 1; fi
t0=$(date +%s); echo "   merged at $(now), main $(main_sha)"
for i in $(seq 1 120); do
  v=$(kubectl -n storefront get deploy catalog -o json | jq -r '[.spec.template.spec.containers[0].env[] | select(.name == "DB_POOL_MAX") | .value][0]')
  [ "$v" = 12 ] && { echo "   $(now) Argo CD applied it: DB_POOL_MAX=12 in the Deployment after $(( $(date +%s) - t0 )) s"; break; }
  sleep 5
done
kubectl -n storefront rollout status deploy/catalog --timeout=180s >/dev/null && echo "   $(now) rollout complete after $(( $(date +%s) - t0 )) s; $(cluster)"

echo; echo "== $(now) G6 a direct push to main, as the administrator"
work=$(mktemp -d)
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$RT" | base64 -w0)" \
  git clone -q "$GL/root/platform-gitops.git" "$work"
echo "# direct push test" >> "$work/README-direct-push.md"
git -C "$work" add -A && git -C "$work" -c user.name=root -c user.email=root@lab.local commit -q -m "G6 direct push"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "$RT" | base64 -w0)" \
  git -C "$work" push origin HEAD:main 2>&1 | grep -E "remote:|rejected|error" | sed 's/^/   /'
rm -rf "$work"
echo "   main: $(main_sha)"
