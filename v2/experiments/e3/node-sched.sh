#!/usr/bin/env bash
# CPU scheduling on the CPUs of one Kind node in a time window (node-exporter's schedstat).
#   bash v2/experiments/e3/node-sched.sh <node> <start-iso> <end-iso>
# A Kind node is a container pinned to a set of CPUs of the WSL VM (docker update --cpuset-cpus,
# chapter 1). node-exporter reports, per CPU of the VM: time running a task and time tasks spent
# runnable but waiting for that CPU. For the node's CPUs: busy fraction and waiting time per
# second of wall time (0.30 = on average 0.3 tasks were waiting for a CPU), and the VM's CPU
# pressure (PSI "some": share of time at least one task waited).
set -euo pipefail
NODE=${1:?node}; S=${2:?start}; E=${3:?end}
CPUS=$(docker inspect -f '{{.HostConfig.CpusetCpus}}' "$NODE")          # e.g. 12-15
first=${CPUS%-*}; last=${CPUS#*-}; re=$(seq -s '|' "$first" "$last")
W=$(( $(date -d "$E" +%s) - $(date -d "$S" +%s) ))s; T=$(date -d "$E" +%s)
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
q() { kubectl get --raw "$P/query?time=$T&query=$(jq -rn --arg q "$1" '$q|@uri')" |
  jq -r '.data.result[] | "\(.metric.cpu // "all") \(.value[1] | tonumber | . * 1000 | round / 1000)"'; }
echo "$NODE: CPUs $CPUS, window $S .. $E"
echo "  per CPU: running (share of the CPU busy) | waiting (tasks waiting for it, on average)"
join <(q "max by (cpu) (rate(node_schedstat_running_seconds_total{cpu=~\"$re\"}[$W]))" | sort) \
     <(q "max by (cpu) (rate(node_schedstat_waiting_seconds_total{cpu=~\"$re\"}[$W]))" | sort) |
  awk '{printf "    cpu %-3s running %.3f | waiting %.3f\n", $1, $2, $3}'
echo "  VM CPU pressure (PSI some, share of time): $(q "max(rate(node_pressure_cpu_waiting_seconds_total[$W]))" | awk '{print $2}')"
