#!/usr/bin/env bash
# Why AlertmanagerClusterCrashlooping fires without a restart (E9, chapter 10).
#   bash v2/experiments/e9/clock-drift.sh > v2/evidence/e9/clock-drift.log
# 1. Alertmanager's restarts as the kubelet counts them; 2. process_start_time_seconds of its two
# containers over 3 minutes (Prometheus range query) and changes() over 10 minutes - the alert's input;
# 3. the WSL VM: wall clock, uptime (monotonic) and the kernel's boot time (btime) over 60 s, in WSL and
# in a kind node; 4. the node exporter's view of time synchronisation.
set -uo pipefail
P="/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1"
enc() { python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
query() { kubectl get --raw "$P/query?query=$(enc "$1")"; }
echo "# clock drift and AlertmanagerClusterCrashlooping, $(date -u +%FT%TZ)"
echo "== 1. restarts: $(kubectl -n monitoring get pod alertmanager-kps-alertmanager-0 -o jsonpath='{range .status.containerStatuses[*]}{.name}={.restartCount} {end}') (pod started $(kubectl -n monitoring get pod alertmanager-kps-alertmanager-0 -o jsonpath='{.status.startTime}'))"
echo "== 2. process_start_time_seconds{job=\"kps-alertmanager\"} over the last 3 minutes (sample time -> value)"
query 'process_start_time_seconds{job="kps-alertmanager"}[3m]' | python3 -c '
import json, sys
for r in json.load(sys.stdin)["data"]["result"]:
    print("  container", r["metric"].get("container"))
    for t, v in r["values"]:
        print(f"    {float(t):.0f} -> {float(v):.2f}")'
echo "   changes() over 10 minutes (the alert fires above 4):"
query 'changes(process_start_time_seconds{job="kps-alertmanager"}[10m])' | python3 -c '
import json, sys
for r in json.load(sys.stdin)["data"]["result"]:
    print("    ", r["metric"].get("container"), r["value"][1])'
echo "== 3. wall clock, monotonic uptime and boot time over 60 s"
measure() {  # $1: label; the rest: a command prefix that runs a shell command there
  local label=$1; shift
  local a b
  a=$("$@" sh -c 'echo $(date +%s.%N) $(cut -d" " -f1 /proc/uptime) $(awk "/^btime/ {print \$2}" /proc/stat)')
  sleep 60
  b=$("$@" sh -c 'echo $(date +%s.%N) $(cut -d" " -f1 /proc/uptime) $(awk "/^btime/ {print \$2}" /proc/stat)')
  python3 - "$label" $a $b <<'PY'
import sys
label, d0, u0, b0, d1, u1, b1 = sys.argv[1], *map(float, sys.argv[2:])
print(f"  {label}: wall clock +{d1 - d0:.2f} s, uptime +{u1 - u0:.2f} s "
      f"(monotonic {100 * ((u1 - u0) / (d1 - d0) - 1):+.2f} % against the wall clock), btime {b0:.0f} -> {b1:.0f} ({b1 - b0:+.0f} s)")
PY
}
measure "WSL VM" env
measure "kind node ent-worker3" docker exec ent-worker3
echo "== 4. node exporter: offset and sync status"
query 'node_timex_offset_seconds' | python3 -c '
import json, sys
print("  ", sorted((r["metric"]["instance"], r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]))'
query 'node_timex_sync_status' | python3 -c '
import json, sys
print("  ", sorted((r["metric"]["instance"], r["value"][1]) for r in json.load(sys.stdin)["data"]["result"]))'
