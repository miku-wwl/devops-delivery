#!/usr/bin/env bash
# PostgreSQL failover drills (E7, chapter 8), measured with the drill writer (writer.py).
#   bash v2/experiments/e7/failover.sh <run> <writer-node> rollout "<publish message>"
#   bash v2/experiments/e7/failover.sh <run> <writer-node> promote <instance>
#   bash v2/experiments/e7/failover.sh <run> <writer-node> delete
#   bash v2/experiments/e7/failover.sh <run> <writer-node> freeze <seconds>
#   bash v2/experiments/e7/failover.sh <run> <writer-node> cut-freeze <cut-seconds> <freeze-seconds>
# rollout: publish v2/gitops (a pending change of pg-main) and wait for the rolling update.
# promote: planned switchover (kubectl cnpg promote). delete: force-delete the primary pod. freeze: docker pause the primary's node ([注入]).
# cut-freeze: drop replication (replica pods -> primary :5432) on the primary's node for
# <cut-seconds> (chain E7CUT), then freeze that node. The chain is removed and the node unpaused
# in every case (trap). DIRECT=1: a second writer (<run>-z, evidence/e7/<run>-z/) connects straight
# to the primary's pod address instead of pg-main-rw. Evidence in evidence/e7/<run>/: run.txt, writer.log, rows.txt,
# report.txt, watch.txt (pg-watch.sh), events.txt, operator.log.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RUN=${1:?run}; WNODE=${2:?writer node}; MODE=${3:?mode}; shift 3
OUT="$ROOT/v2/evidence/e7/$RUN"; mkdir -p "$OUT"
exec > >(tee "$OUT/run.txt") 2>&1
now() { date -u +%T.%3N; }
PNODE=
uncut() { [ -n "$PNODE" ] && docker exec "$PNODE" sh -c 'while iptables -D FORWARD -j E7CUT 2>/dev/null; do :; done; iptables -F E7CUT 2>/dev/null; iptables -X E7CUT 2>/dev/null' || true; }
cleanup() {
  if [ -n "$PNODE" ] && [ "$(docker inspect -f '{{.State.Paused}}' "$PNODE")" = true ]; then docker unpause "$PNODE"; echo "$(now) trap: unpaused $PNODE"; fi
  uncut
  [ -n "${watcher:-}" ] && kill "$watcher" 2>/dev/null
}
trap cleanup EXIT
healthy() { # until the cluster is healthy with 3 ready instances and no switch pending
  local i s
  for i in $(seq 1 600); do
    s=$(kubectl -n data get cluster pg-main -o json | jq -r '"\(.status.phase)|\(.status.readyInstances)|\(.status.currentPrimary == .status.targetPrimary)"')
    [ "$s" = "Cluster in healthy state|3|true" ] && { echo "$(now) healthy again"; return 0; }
    sleep 1
  done
  echo "$(now) NOT healthy after 600 s: $s"; return 1
}

primary=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')
PNODE=$(kubectl -n data get pod "$primary" -o jsonpath='{.spec.nodeName}')
case $MODE in rollout|promote) PNODE= ;; esac   # nothing to unpause or uncut
if [ "$(kubectl -n data get pod "$primary" -o jsonpath='{.spec.nodeName}')" = "$WNODE" ]; then
  echo "the writer node $WNODE hosts the primary $primary"; exit 1
fi
echo "== $(now) run $RUN: primary $primary on $(kubectl -n data get pod "$primary" -o jsonpath='{.spec.nodeName}'), writer on $WNODE, mode $MODE $*"
kubectl -n data exec "$primary" -c postgres -- psql -U postgres -tAc \
  "select 'replication: ' || string_agg(application_name || '=' || state || '/' || sync_state, ' ') from pg_stat_replication"
since=$(date -u +%FT%TZ)
bash "$HERE/writer.sh" start "$RUN" "$WNODE" 50 2
if [ "${DIRECT:-0}" = 1 ]; then
  bash "$HERE/writer.sh" start "$RUN-z" "$WNODE" 50 2 "$(kubectl -n data get pod "$primary" -o jsonpath='{.status.podIP}')"
fi
bash "$HERE/pg-watch.sh" > "$OUT/watch.txt" 2>&1 &
watcher=$!
sleep 20
T0=$(date +%s.%N)
echo "== $(now) fault: $MODE $*"
case $MODE in
  rollout)
    bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" fd38028 "${1:?message}"
    kubectl -n argocd annotate app pg-main argocd.argoproj.io/refresh=normal --overwrite >/dev/null
    sleep 30; healthy ;;
  promote)
    kubectl cnpg promote pg-main "${1:?instance}" -n data
    sleep 5; healthy ;;
  delete)
    kubectl -n data delete pod "$primary" --grace-period=0 --force 2>&1 | grep -v "^Warning"
    sleep 5; healthy ;;
  freeze)
    docker pause "$PNODE" >/dev/null; echo "$(now) paused $PNODE"
    sleep "${1:?seconds}"
    docker unpause "$PNODE" >/dev/null; echo "$(now) unpaused $PNODE"
    healthy ;;
  cut-freeze)
    pip=$(kubectl -n data get pod "$primary" -o jsonpath='{.status.podIP}')
    rips=$(kubectl -n data get pods -l cnpg.io/cluster=pg-main,cnpg.io/instanceRole=replica -o jsonpath='{.items[*].status.podIP}')
    # close the current WAL segment first: the next one reaches the archive only after archive_timeout
    # (5 min), so nothing written during the cut can reach the replicas through the archive either
    echo "$(now) closed WAL segment $(kubectl -n data exec "$primary" -c postgres -- psql -U postgres -tAc 'select pg_walfile_name(pg_switch_wal())')"
    docker exec -i "$PNODE" sh -s "$pip" $rips <<'SH'
p=$1; shift
iptables -N E7CUT
for r in "$@"; do
  iptables -A E7CUT -s "$r" -d "$p" -p tcp --dport 5432 -j DROP
  iptables -A E7CUT -s "$p" -d "$r" -p tcp --sport 5432 -j DROP
done
iptables -I FORWARD 1 -j E7CUT
iptables -S E7CUT | sed 's/^/  /'
SH
    echo "$(now) replication cut on $PNODE"
    sleep "${1:?cut seconds}"
    kubectl -n data exec "$primary" -c postgres -- psql -U postgres -tAc \
      "select 'replication before the freeze: ' || coalesce(string_agg(application_name || '=' || state, ' '), 'none') from pg_stat_replication"
    docker pause "$PNODE" >/dev/null; echo "$(now) paused $PNODE"
    sleep "${2:?freeze seconds}"
    docker unpause "$PNODE" >/dev/null; echo "$(now) unpaused $PNODE"
    uncut; echo "$(now) replication cut removed"
    healthy ;;
  *) echo "unknown mode $MODE"; exit 1 ;;
esac
sleep 30
bash "$HERE/writer.sh" stop "$RUN"
[ "${DIRECT:-0}" = 1 ] && bash "$HERE/writer.sh" stop "$RUN-z"
kill "$watcher" 2>/dev/null; watcher=
echo "== report (t = seconds after the fault)"
bash "$HERE/writer.sh" report "$RUN" "$T0" | tee "$OUT/report.txt"
if [ "${DIRECT:-0}" = 1 ]; then
  echo "== report of the direct writer (connected to the old primary's address)"
  bash "$HERE/writer.sh" report "$RUN-z" "$T0" | tee "$OUT/report-direct.txt"
fi
echo "== timeline (lines where something changed)"
awk '{sig = $0; sub(/^[^ ]+ /, "", sig)} sig != prev {print; prev = sig}' "$OUT/watch.txt" | sed 's/^/  /'
kubectl -n data get events --sort-by=.lastTimestamp -o json |
  jq -r --arg s "$since" '.items[] | select((.lastTimestamp // .eventTime) >= $s) | "\(.lastTimestamp // .eventTime) \(.involvedObject.kind)/\(.involvedObject.name) \(.reason): \(.message)"' > "$OUT/events.txt"
kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg --since-time="$since" 2>/dev/null |
  jq -rc 'select(tostring | test("pg-main")) | select(.msg | test("(?i)switchover|failover|promot|primary|fenc|rewind|unhealthy|not ready")) | "\(.ts) \(.msg) \(.currentPrimary // "") \(.targetPrimary // "")"' 2>/dev/null > "$OUT/operator.log"
echo "== $(wc -l < "$OUT/events.txt") events, $(wc -l < "$OUT/operator.log") operator log lines; primary now $(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')"
