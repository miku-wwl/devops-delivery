#!/usr/bin/env bash
# Point-in-time recovery drill on the storefront's orders (E7, chapter 8).
#   bash v2/experiments/e7/pitr.sh <run> [k6-rate] [detect-seconds]
# 1. k6 keeps the storefront busy (browse + orders) for the whole drill.
# 2. The current WAL segment is closed (known starting point). The accident: a cleanup job meant to delete FAILED orders older than 30 days runs without its
#    conditions - DELETE FROM orders WHERE created_at < now() - as the orders role, on the primary.
#    The job logs its start time from the server clock (the recovery target).
#    Before it, only for checking the result afterwards: the list of order ids (ground truth).
# 3. <detect-seconds> later the accident is "noticed". The recovery cluster pg-pitr (one instance,
#    pg-pitr.yaml.tpl) is restored from the archive to the job's start time. If the WAL around the
#    target is not archived yet, that restore cannot reach the target: the script records the
#    attempt, forces a WAL switch on the primary and tries again.
# 4. The deleted rows are copied from pg-pitr back into production (staging table, INSERT ... ON
#    CONFLICT DO NOTHING): orders created after the accident stay untouched.
# 5. Checks against the ground truth; pg-pitr is deleted.
# Evidence: evidence/e7/<run>/ (run.txt, k6.txt, recovery-*.txt, ids-summary.txt: counts and hashes
# of the id lists, which stay in a temporary directory - hundreds of thousands of uuids).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RUN=${1:?run}; RATE=${2:-5}; DETECT=${3:-60}
OUT="$ROOT/v2/evidence/e7/$RUN"; mkdir -p "$OUT"
exec > >(tee "$OUT/run.txt") 2>&1
now() { date -u +%T.%3N; }
# ids in $1 but not in $2 (both sorted bytewise: PostgreSQL orders uuids like LC_ALL=C)
missing() { LC_ALL=C comm -23 <(LC_ALL=C sort "$IDS/$1.txt") <(LC_ALL=C sort "$IDS/$2.txt") | wc -l; }
prim() { kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}'; }
sqlp() { kubectl -n data exec "$(prim)" -c postgres -- psql -U postgres -d orders -tAc "$1"; }
sqlr() { kubectl -n data exec pg-pitr-1 -c postgres -- psql -U postgres -d orders -tAc "$1"; }
IDS=$(mktemp -d)
cleanup() {
  rm -rf "$IDS"
  [ -n "${k6pid:-}" ] && kill "$k6pid" 2>/dev/null
  [ "${KEEP:-0}" = 1 ] || kubectl -n data delete cluster pg-pitr --ignore-not-found --wait=false >/dev/null
}
trap cleanup EXIT
IMAGE=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.image}')
render() { sed -e "s|\${IMAGE}|$IMAGE|" -e "s|\${TARGET_TIME}|$1|" "$HERE/pg-pitr.yaml.tpl"; }
restore() { # target-time label -> 0 when pg-pitr became ready
  local t0 i phase
  kubectl -n data delete cluster pg-pitr --ignore-not-found --wait=true >/dev/null 2>&1
  kubectl -n data wait --for=delete pod -l cnpg.io/cluster=pg-pitr --timeout=120s >/dev/null 2>&1
  t0=$(date +%s)
  render "$1" | kubectl apply -f - >/dev/null
  echo "$(now) [$2] pg-pitr created, target $1"
  for i in $(seq 1 120); do
    phase=$(kubectl -n data get cluster pg-pitr -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$phase" = "Cluster in healthy state" ]; then
      echo "$(now) [$2] pg-pitr healthy after $(( $(date +%s) - t0 )) s"; return 0
    fi
    # the restore runs in a job pod first (pg-pitr-1-full-recovery-*)
    if kubectl -n data get pods -l cnpg.io/cluster=pg-pitr --no-headers 2>/dev/null | grep -qE "Error|CrashLoopBackOff"; then
      echo "$(now) [$2] restore failed after $(( $(date +%s) - t0 )) s (phase: $phase)"
      kubectl -n data get pods -l cnpg.io/cluster=pg-pitr --no-headers | sed 's/^/  /'
      for p in $(kubectl -n data get pods -l cnpg.io/cluster=pg-pitr -o name); do
        kubectl -n data logs "$p" --all-containers 2>/dev/null |
          jq -rc 'select(.record.error_severity != null) | select(.record.message | test("recovery|target|restored|redo")) | "\(.record.log_time[11:23]) \(.record.error_severity): \(.record.message)"' 2>/dev/null | tail -8 | sed 's/^/  /'
      done > "$OUT/recovery-$2.txt"
      cat "$OUT/recovery-$2.txt"
      return 1
    fi
    sleep 5
  done
  echo "$(now) [$2] pg-pitr not healthy after 600 s (phase: $phase)"; return 1
}

echo "== $(now) run $RUN: primary $(prim), k6 $RATE it/s, accident noticed after $DETECT s"
bash "$ROOT/v2/platform/cluster/lb-limits.sh" >/dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
BASE_URL=$GW RATE=$RATE DURATION=30m SUMMARY="$OUT/k6.json" \
  taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1 &
k6pid=$!
sleep 60
echo "== $(now) before: $(sqlp "select count(*) || ' orders, newest ' || max(created_at) from orders")"
sqlp "copy (select id from orders order by id) to stdout" > "$IDS/ids-before.txt"
echo "   archiver: $(sqlp "select 'last archived ' || last_archived_wal || ' at ' || last_archived_time || ', current ' || pg_walfile_name(pg_current_wal_lsn()) from pg_stat_archiver")"

# a known starting point: the current segment is closed now, so the next one reaches the archive
# only through archive_timeout, 5 minutes later - the worst case for a restore right after the accident
echo "   closed segment $(sqlp "select pg_walfile_name(pg_switch_wal())") right before the accident"
echo "== $(now) the cleanup job (as role orders)"
# ACCIDENT_WHERE: what the broken job deletes (default: everything; pitr-2: only recent orders)
JOB=$(kubectl -n data exec -i "$(prim)" -c postgres -- psql -U postgres -d orders -tAq <<SQL
SET ROLE orders;
SELECT pg_current_wal_lsn() AS lsn0 \gset
SELECT 'job start ' || to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') || '+00';
-- meant: WHERE status = 'FAILED' AND created_at < now() - interval '30 days'
WITH d AS (DELETE FROM orders WHERE ${ACCIDENT_WHERE:-created_at < now()} RETURNING 1) SELECT 'deleted ' || count(*) FROM d;
SELECT 'wal written meanwhile ' || pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), :'lsn0'));
SQL
)
echo "$JOB" | sed "s/^/   /"
TARGET=$(sed -n 's/^job start //p' <<<"$JOB")
DELETED=$(sed -n 's/^deleted //p' <<<"$JOB")
echo "   recovery target = job start = $TARGET; rows deleted: $DELETED (ids-before: $(wc -l < "$IDS/ids-before.txt"))"
sleep "$DETECT"
T_DETECT=$(date +%s)
echo "== $(now) accident noticed; orders now: $(sqlp "select count(*) from orders")"
echo "   archiver: $(sqlp "select 'last archived ' || last_archived_wal || ' at ' || last_archived_time || ', current ' || pg_walfile_name(pg_current_wal_lsn()) from pg_stat_archiver")"

if ! restore "$TARGET" attempt-1; then
  echo "== $(now) forcing a WAL switch on the primary: $(sqlp "select pg_walfile_name(pg_switch_wal())") is closed and archived next"
  for i in $(seq 1 30); do
    a=$(sqlp "select last_archived_time > now() - interval '30 seconds' from pg_stat_archiver"); [ "$a" = t ] && break; sleep 2
  done
  echo "   archiver: $(sqlp "select 'last archived ' || last_archived_wal || ' at ' || last_archived_time from pg_stat_archiver")"
  restore "$TARGET" attempt-2 || { echo "== recovery failed twice; giving up"; exit 1; }
fi

echo "== $(now) in pg-pitr: $(sqlr "select count(*) || ' orders, newest ' || max(created_at) from orders")"
sqlr "copy (select id from orders order by id) to stdout" > "$IDS/ids-recovered.txt"
echo "   ids before the accident missing in pg-pitr: $(missing ids-before ids-recovered)"

echo "== $(now) copy back (staging table, existing ids untouched)"
sqlp "drop table if exists orders_restored; create table orders_restored (like orders including all)" >/dev/null
kubectl -n data exec pg-pitr-1 -c postgres -- psql -U postgres -d orders -c "copy orders to stdout" |
  kubectl -n data exec -i "$(prim)" -c postgres -- psql -U postgres -d orders -c "copy orders_restored from stdin"
echo "   inserted: $(sqlp "with i as (insert into orders select * from orders_restored on conflict (id) do nothing returning 1) select count(*) from i")"
sqlp "drop table orders_restored" >/dev/null
T_DONE=$(date +%s)
sqlp "copy (select id from orders order by id) to stdout" > "$IDS/ids-after.txt"
echo "== $(now) after: $(sqlp "select count(*) from orders") orders"
echo "   ids before the accident missing now: $(missing ids-before ids-after)"
echo "   orders created after the accident (kept): $(sqlp "select count(*) from orders where created_at >= '$TARGET'")"
# a restored row is the version of the target time: changes that the services tried to make to it
# while it was missing (e.g. PENDING -> CONFIRMED after the payment) found no row and are not in it
echo "   restored orders by status: $(sqlp "select string_agg(status || '=' || n, ' ') from (select status, count(*) n from orders where created_at < '$TARGET' group by status order by status) s")"
echo "   of them PENDING and created in the last 60 s before the accident: $(sqlp "select count(*) from orders where status = 'PENDING' and created_at between timestamptz '$TARGET' - interval '60 seconds' and '$TARGET'")"
echo "   time from noticing to the rows being back: $(( T_DONE - T_DETECT )) s"
{ echo "# order id lists of $RUN (kept outside Git); sorted bytewise (LC_ALL=C)"
  for f in ids-before ids-recovered ids-after; do
    echo "$f: $(wc -l < "$IDS/$f.txt") ids, sha256 $(LC_ALL=C sort "$IDS/$f.txt" | sha256sum | cut -c1-64)"
  done
  echo "in ids-before, missing in ids-recovered: $(missing ids-before ids-recovered)"
  echo "in ids-before, missing in ids-after: $(missing ids-before ids-after)"
  echo "in ids-recovered, missing in ids-after: $(missing ids-recovered ids-after)"
} > "$OUT/ids-summary.txt"
kill "$k6pid" 2>/dev/null; wait "$k6pid" 2>/dev/null; k6pid=
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" >/dev/null 2>&1
grep -E "requests=|browse:|order:" "$OUT/k6.txt" | sed 's/^/   /'
