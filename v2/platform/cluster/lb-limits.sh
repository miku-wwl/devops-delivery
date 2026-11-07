#!/usr/bin/env bash
# Raise the open-file limit of the load balancers that cloud-provider-kind runs for
# LoadBalancer Services (one Envoy container "kindccm-*" per Service, on the Docker network).
#   bash v2/platform/cluster/lb-limits.sh [soft-limit]
# Why (chapter 4, E3): the container starts Envoy from a bash loop with the Docker default soft
# limit of 1024 open files. Envoy needs two descriptors per proxied connection, so at ~500
# concurrent client connections socket(2) fails with "Too many open files"; Envoy 1.33.2 then
# hits an internal assertion ("envoy bug failure ... Client socket failure") and crashes with a
# segmentation fault. The bash loop restarts it within ~2 s, every client connection is dropped,
# the clients reconnect at once, and the cycle repeats every ~5 s. A cloud load balancer has no
# such limit, so this is a defect of the lab, not of the system under test.
# The fix sets the soft limit of the bash loop (inherited by every Envoy it restarts) and of the
# running Envoy, by host PID with prlimit (needs root: sudo). It does not survive a re-creation
# of the container, so the load scripts run it before every test (it is idempotent).
set -euo pipefail
SOFT=${1:-65536}
for c in $(docker ps --format '{{.Names}}' | grep -E '^kindccm-' || true); do
  pid1=$(docker inspect -f '{{.State.Pid}}' "$c")
  for p in "$pid1" $(pgrep -P "$pid1" -x envoy || true); do
    hard=$(sudo -n prlimit --pid "$p" --nofile --noheadings --output HARD | tr -d ' ')
    before=$(sudo -n prlimit --pid "$p" --nofile --noheadings --output SOFT | tr -d ' ')
    if [ "$before" != "$SOFT" ]; then
      sudo -n prlimit --pid "$p" --nofile="$SOFT:$hard"
    fi
    echo "$c pid $p ($(cat /proc/"$p"/comm)): open files soft limit $before -> $(sudo -n prlimit --pid "$p" --nofile --noheadings --output SOFT | tr -d ' ') (hard $hard)"
  done
done
