#!/usr/bin/env bash
# For every step of a step load: where the gateway waited, and what its main thread did.
#   bash v2/experiments/e3/where-waits.sh <label>
# Reads the step windows from evidence/e3/steps-<label>/window-*.json (step-ramp.sh) and the
# main-thread samples from evidence/e3/steps-<label>/sched.txt (sched-sample.sh), and runs
# gateway-wait.sh for each window. Works afterwards too, as long as Prometheus still has the data.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../../evidence/e3/steps-${1:?label}"
for w in $(ls "$OUT"/window-*.json | awk -F/ '{print $NF, $0}' | sort -t- -k2 -n | cut -d" " -f2); do
  rate=$(basename "$w" .json | cut -d- -f2)
  s=$(jq -r .start "$w"); e=$(jq -r .end "$w")
  echo "=== step $rate it/s ($s .. $e)"
  bash "$HERE/gateway-wait.sh" "$s" "$e"
  if [ -s "$OUT/sched.txt" ]; then echo "  gateway main thread, 10 s samples in the window: $(awk -v s="${s:11:8}" -v e="${e:11:8}" \
    '$1 >= s && $1 <= e {c += substr($4, 5); r += substr($5, 6); k++} END {if (k) printf "cpu=%.3f runq=%.3f (%d samples)", c / k, r / k, k}' "$OUT/sched.txt")"; fi
done
