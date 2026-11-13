#!/usr/bin/env bash
# Rebuilds R3 and R4 (E8, chapter 9; hypotheses W1-W5 in evidence/e8/waves-prediction.md): the
# runbook of chapter 8 (experiments/e7/rebuild.sh) end to end, without pauses between the steps -
# destroy, DR change (pg-main born from the previous archive, archiving under the next name), create,
# bootstrap, wait for the applications; OpenBao is restored as soon as its pod exists (in R2 that
# step was started by hand).
#   bash v2/experiments/e7/rebuild.sh before <run>  # first: state before, the drill writer
#   (stream the writer's log to evidence/e7/<run>/writer.log)
#   bash v2/experiments/e8/rebuild-run.sh <run>      # then this; evidence in evidence/e7/<run>/
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RUN=${1:?run, e.g. r4}
E7="$ROOT/v2/experiments/e7"; OUT="$ROOT/v2/evidence/e7/$RUN"
mark() { echo "== $(date -u +%T) (T0 + $(( $(date +%s) - $(cat "$OUT/t0") )) s) $1"; }
bash "$E7/rebuild.sh" destroy "$RUN"
bash "$E7/rebuild.sh" dr-change > "$OUT/dr-change.txt" 2>&1
{ mark create.sh; bash "$ROOT/v2/platform/cluster/create.sh"; mark "create.sh exit $?"; } > "$OUT/create.txt" 2>&1
{ mark bootstrap.sh; bash "$ROOT/v2/platform/bootstrap/bootstrap.sh"; mark "bootstrap.sh exit $?"; } > "$OUT/bootstrap.txt" 2>&1
( until kubectl -n secrets get pod openbao-0 >/dev/null 2>&1; do sleep 3; done
  { mark "openbao-0 exists"; } > "$OUT/openbao-ready.txt"
  bash "$E7/rebuild.sh" restore "$RUN" ) &
restore=$!
{ mark wait-apps.sh; bash "$ROOT/v2/platform/bootstrap/wait-apps.sh" 1800; mark "wait-apps.sh exit $?"; } > "$OUT/wait-apps.txt" 2>&1
wait $restore
bash "$E7/rebuild.sh" verify "$RUN"
mark done >> "$OUT/wait-apps.txt"
