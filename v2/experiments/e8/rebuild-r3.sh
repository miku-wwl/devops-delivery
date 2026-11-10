#!/usr/bin/env bash
# Rebuild R3 (E8, chapter 9; hypotheses W1-W5 in evidence/e8/waves-prediction.md): the runbook of
# chapter 8 (experiments/e7/rebuild.sh) end to end, without pauses between the steps - destroy, DR
# change (pg-main born from pg-main-r2, archiving as pg-main-r3), create, bootstrap, wait for the
# applications; OpenBao is restored as soon as its pod exists (in R2 that step was started by hand).
#   bash v2/experiments/e7/rebuild.sh before r3     # first: state before, the drill writer
#   (stream the writer's log to evidence/e7/r3/writer.log)
#   bash v2/experiments/e8/rebuild-r3.sh             # then this; evidence in evidence/e7/r3/
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
E7="$ROOT/v2/experiments/e7"; OUT="$ROOT/v2/evidence/e7/r3"
mark() { echo "== $(date -u +%T) (T0 + $(( $(date +%s) - $(cat "$OUT/t0") )) s) $1"; }
bash "$E7/rebuild.sh" destroy r3
bash "$E7/rebuild.sh" dr-change > "$OUT/dr-change.txt" 2>&1
{ mark create.sh; bash "$ROOT/v2/platform/cluster/create.sh"; mark "create.sh exit $?"; } > "$OUT/create.txt" 2>&1
{ mark bootstrap.sh; bash "$ROOT/v2/platform/bootstrap/bootstrap.sh"; mark "bootstrap.sh exit $?"; } > "$OUT/bootstrap.txt" 2>&1
( until kubectl -n secrets get pod openbao-0 >/dev/null 2>&1; do sleep 3; done
  { mark "openbao-0 exists"; } > "$OUT/openbao-ready.txt"
  bash "$E7/rebuild.sh" restore r3 ) &
restore=$!
{ mark wait-apps.sh; bash "$ROOT/v2/platform/bootstrap/wait-apps.sh" 1800; mark "wait-apps.sh exit $?"; } > "$OUT/wait-apps.txt" 2>&1
wait $restore
bash "$E7/rebuild.sh" verify r3
mark done >> "$OUT/wait-apps.txt"
