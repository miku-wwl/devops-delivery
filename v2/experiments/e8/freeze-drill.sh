#!/usr/bin/env bash
# Change freeze drill (E8, chapter 9; hypotheses F1-F4 and D1-D2 in evidence/e8/freeze-prediction.md).
#   bash v2/experiments/e8/freeze-drill.sh [lead-minutes] [window-minutes]
# Two keys over the same minutes: a GitLab deploy freeze (the gate's job "freeze") and an Argo CD deny
# window on the project storefront (manualSync allowed).
#  1. merge request: the drill's deny window (starting in <lead> minutes, <window> minutes long) and
#     the job "freeze" (already in v2/gitops); then the GitLab freeze period over the same minutes;
#  2. in the window: alice's ordinary merge request (catalog LOG_LEVEL) - and a merge attempt;
#  3. an emergency merge request ("[emergency]": DB_POOL_MAX +2 for orders and catalog);
#  4. Argo CD should hold it back; after 120 s an operator syncs catalog by hand;
#  5. the window ends: when does orders follow on its own?
#  6. the GitLab deployments of these syncs, and the merge requests GitLab links to them;
#  7. the freeze period is deleted (also by the trap), the drill window removed by a last merge request.
# Evidence: evidence/e8/freeze/run.txt
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
GO="$ROOT/v2/gitops"
OUT="$ROOT/v2/evidence/e8/freeze"; mkdir -p "$OUT"
exec > >(tee "$OUT/run.txt") 2>&1
LEAD=${1:-4}; WIN=${2:-14}
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
api() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$@"; }
G=http://localhost:8929/api/v4/projects/root%2Fplatform-gitops
now() { date -u +%T; }
app() { kubectl -n argocd get app "storefront-$1-prod" -o jsonpath="{.status.sync.status} {.status.health.status} op={.status.operationState.phase} started={.status.operationState.startedAt} finished={.status.operationState.finishedAt} rev={.status.sync.revision}" | cut -c1-200; }
FP=
cleanup() { [ -n "$FP" ] && api -X DELETE "$G/freeze_periods/$FP" >/dev/null && echo "== $(now) freeze period $FP deleted"; FP=; }
trap cleanup EXIT
T0=$(date -u +%FT%TZ)
START=$(( ( $(date +%s) + LEAD * 60 ) / 60 * 60 )); END=$(( START + WIN * 60 ))
CRON_S="$(date -u -d @$START '+%-M %-H') * * *"; CRON_E="$(date -u -d @$END '+%-M %-H') * * *"
echo "== $(now) drill window $(date -u -d @$START +%T) - $(date -u -d @$END +%T) UTC (cron '$CRON_S', ${WIN}m)"

echo "== $(now) 1. the deny window and the job freeze, through the gate"
sed -i "/^  syncWindows:/a\\    - {kind: deny, schedule: \"$CRON_S\", duration: ${WIN}m, applications: [\"*\"], manualSync: true, timeZone: UTC}   # E8 freeze drill, removed after it" \
  "$GO/platform/apps/00-projects.yaml"
bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" fd38028 "e8: change freeze - deny window for the drill, job freeze" 2>&1 | sed 's/^/  /'
kubectl -n argocd annotate app platform-root argocd.argoproj.io/refresh=normal --overwrite >/dev/null
FP=$(api -X POST "$G/freeze_periods" --data-urlencode "freeze_start=$CRON_S" --data-urlencode "freeze_end=$CRON_E" --data cron_timezone=UTC | jq -r .id)
echo "== $(now) GitLab freeze period $FP: $(api "$G/freeze_periods/$FP" | jq -c '{freeze_start, freeze_end, cron_timezone}')"
for i in $(seq 1 30); do
  w=$(kubectl -n argocd get appproject storefront -o jsonpath='{.spec.syncWindows[*].schedule}')
  case "$w" in *"$CRON_S"*) break ;; esac; sleep 5
done
echo "== $(now) project storefront, sync windows in the cluster: $w"
sleep $(( START - $(date +%s) + 20 ))

echo "== $(now) 2. F1: alice's ordinary change inside the freeze"
out=$(bash "$ROOT/v2/platform/gitops/mr.sh" propose fd38028 "catalog: LOG_LEVEL WARNING" --as alice \
  --edit "sed -i 's/^  LOG_LEVEL: INFO .*/  LOG_LEVEL: WARNING/' envs/prod/storefront/services/catalog.yaml" 2>&1); echo "$out" | sed 's/^/  /'
IID=$(echo "$out" | grep -o 'MR ![0-9]*' | head -1 | tr -d 'MR !')
if [ -n "$IID" ]; then
  PIPE=$(api "$G/merge_requests/$IID/pipelines" | jq -r '.[0].id')
  api "$G/pipelines/$PIPE/jobs" | jq -r '.[] | "  job \(.name): \(.status)"'
  JOB=$(api "$G/pipelines/$PIPE/jobs" | jq -r '.[] | select(.name == "freeze") | .id')
  [ -n "$JOB" ] && api "$G/jobs/$JOB/trace" | grep "deploy freeze" | sed 's/^/  log: /'
  bash "$ROOT/v2/platform/gitops/mr.sh" merge "$IID" 2>&1 | sed 's/^/  /'
  bash "$ROOT/v2/platform/gitops/mr.sh" close "$IID" 2>&1 | sed 's/^/  /'
fi

echo "== $(now) 3. F2: the emergency change"
sed -i 's/^  DB_POOL_MAX: "10"$/  DB_POOL_MAX: "12"   # E8 freeze drill: the emergency change/' "$GO/envs/prod/storefront/services/orders.yaml"
sed -i 's/^  DB_POOL_MAX: "12"   # E8: merge request !8.*/  DB_POOL_MAX: "14"   # E8: !8 by alice (12), +2 in the freeze drill (the emergency change)/' "$GO/envs/prod/storefront/services/catalog.yaml"
grep -h "DB_POOL_MAX" "$GO/envs/prod/storefront/services/orders.yaml" "$GO/envs/prod/storefront/services/catalog.yaml" | sed 's/^/  /'
bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" fd38028 "[emergency] orders, catalog: DB_POOL_MAX +2 (pool exhaustion)" 2>&1 | sed 's/^/  /'
T_MERGED=$(date +%s); echo "== $(now) merged"
EIID=$(api "$G/merge_requests?state=merged&order_by=updated_at&per_page=1" | jq -r '.[0].iid')
EPIPE=$(api "$G/merge_requests/$EIID/pipelines" | jq -r '.[0].id')
JOB=$(api "$G/pipelines/$EPIPE/jobs" | jq -r '.[] | select(.name == "freeze") | .id')
[ -n "$JOB" ] && api "$G/jobs/$JOB/trace" | grep "deploy freeze" | sed 's/^/  log (!'"$EIID"'): /'

echo "== $(now) 4. F3: Argo CD inside the deny window"
for a in catalog orders; do kubectl -n argocd annotate app "storefront-$a-prod" argocd.argoproj.io/refresh=normal --overwrite >/dev/null; done
for t in 30 60 90 120; do
  sleep $(( T_MERGED + t - $(date +%s) ))
  echo "  +${t}s catalog: $(app catalog)"; echo "  +${t}s orders:  $(app orders)"
done
kubectl -n argocd logs argocd-application-controller-0 --since=4m | grep -i "window" | grep "storefront-orders-prod" | tail -2 | cut -c1-300 | sed 's/^/  log: /'
REV=$(kubectl -n argocd get app storefront-catalog-prod -o jsonpath='{.status.sync.revision}')
echo "== $(now) the operator syncs catalog by hand (revision ${REV:0:12})"
kubectl -n argocd patch application storefront-catalog-prod --type merge \
  -p "{\"operation\":{\"initiatedBy\":{\"username\":\"operator-e8-freeze-drill\"},\"sync\":{\"revision\":\"$REV\"}}}" >/dev/null
for i in $(seq 1 60); do
  s=$(app catalog); case "$s" in "Synced Healthy op=Succeeded"*) break ;; esac; sleep 3
done
echo "== $(now) catalog: $s"
echo "  orders: $(app orders)"

echo "== $(now) 5. F4: waiting for the end of the window ($(date -u -d @$END +%T))"
sleep $(( END - $(date +%s) ))
for i in $(seq 1 100); do
  s=$(app orders); case "$s" in "Synced Healthy op=Succeeded"*) break ;; esac; sleep 3
done
T_ORD=$(date +%s); echo "== $(now) orders: $s ($((T_ORD - END)) s after the end of the window)"

echo "== $(now) 6. D1/D2: the GitLab deployments since $T0"
api "$G/deployments?updated_after=$T0&order_by=updated_at&sort=asc&per_page=50" | jq -r '.[] | "  #\(.id) \(.environment.name) \(.status) \(.sha[0:12]) created \(.created_at) by \(.user.username[0:12])"'
for d in $(api "$G/deployments?updated_after=$T0&order_by=updated_at&sort=asc&per_page=50" | jq -r '.[].id'); do
  echo "  deployment #$d merge requests: $(api "$G/deployments/$d/merge_requests" | jq -r '[.[] | "!\(.iid)"] | join(" ")')"
done

echo "== $(now) 7. cleanup"
cleanup
sed -i '/# E8 freeze drill, removed after it/d' "$GO/platform/apps/00-projects.yaml"
bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" fd38028 "e8: change freeze - drill window removed, year-end freeze stays" 2>&1 | sed 's/^/  /'
echo "== $(now) done"
