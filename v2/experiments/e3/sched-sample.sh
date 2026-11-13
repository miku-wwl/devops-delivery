#!/usr/bin/env bash
# CPU and run-queue time of a service's main thread, every INTERVAL seconds, from the node.
#   bash v2/experiments/e3/sched-sample.sh <service> <seconds> [interval]
# /proc/<pid>/task/<tid>/schedstat holds the thread's time on a CPU and its time spent runnable
# but waiting for a CPU (nanoseconds). Their rates say whether a single-threaded process that is
# "busy" all the time is computing (cpu) or queued behind other threads of its node (runq).
# Prints one line per interval: UTC time, pod, node, cpu (fraction of one core), runq.
set -euo pipefail
SVC=${1:?service}; SECS=${2:?seconds}; IV=${3:-10}
POD=$(kubectl -n storefront get pods -l app.kubernetes.io/name="$SVC" -o jsonpath='{.items[0].metadata.name}')
NODE=$(kubectl -n storefront get pod "$POD" -o jsonpath='{.spec.nodeName}')
PID=$(docker exec "$NODE" sh -c "for p in \$(pgrep -f 'storefront.$SVC.main'); do
  grep -q $POD /proc/\$p/environ 2>/dev/null && echo \$p; done | head -1")
docker exec "$NODE" timeout -k 3 "$((SECS + 5))" sh -c "
  prev=\$(cat /proc/$PID/task/$PID/schedstat); pt=\$(date +%s%N)
  while true; do sleep $IV
    cur=\$(cat /proc/$PID/task/$PID/schedstat); ct=\$(date +%s%N)
    echo \"\$(date -u +%T) $POD $NODE \$prev \$cur \$pt \$ct\"; prev=\$cur; pt=\$ct
  done" | awk '{dt = $11 - $10   # fields: time pod node | prev cpu runq slices | cur cpu runq slices | t0 t1
    printf "%s %s %s cpu=%.3f runq=%.3f raw=%s,%s,%s,%s,%s,%s\n", $1, $2, $3, ($7 - $4) / dt, ($8 - $5) / dt,
      $4, $5, $7, $8, $10, $11; fflush()}'
