#!/usr/bin/env bash
# E10, K5 re-run follow-up: what a client sees while kube-apiserver restarts (kwok cluster "scale", 10 000 pods).
#   bash v2/experiments/e10/restart-probe.sh
# The re-run of K5 restarted the API server 8 times (cgroup OOM kills) and its clients got 000, 403 and 429
# without APF enabled. Here: restart the container on purpose, then LIST all pods (resourceVersion=0, as the
# flood did) every 0.2 s as the service account e10-flood, and record each status code and message until
# three answers in a row are 200.
set -uo pipefail
K="kubectl --kubeconfig $HOME/.kwok/scale.kubeconfig"; A=kwok-scale-kube-apiserver
SERVER=$($K config view --minify -o jsonpath='{.clusters[0].cluster.server}')
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
( umask 077; printf 'Authorization: Bearer %s\n' "$($K create token e10-flood -n default --duration 1h)" > "$tmp/hdr" )
echo "== $(date -u +%T) $($K get pods -o name | wc -l) pods; docker restart $A"
T0=$(date +%s.%N); docker restart "$A" >/dev/null; echo "  restart returned after $(python3 -c "print(round($(date +%s.%N) - $T0, 1))") s"
ok=0; last=""
for i in $(seq 1 600); do
  c=$(curl -sk -m 30 -o "$tmp/b" -w '%{http_code}' -H @"$tmp/hdr" "$SERVER/api/v1/pods?resourceVersion=0")
  t=$(python3 -c "print(round($(date +%s.%N) - $T0, 1))")
  msg=""; [ "$(stat -c %s "$tmp/b" 2>/dev/null || echo 0)" -lt 4096 ] && msg=$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("message", "")[:160])
except Exception: print("")' "$tmp/b")
  [ "$c $msg" != "$last" ] && echo "  t=${t}s $c $msg"; last="$c $msg"
  [ "$c" = 200 ] && ok=$((ok + 1)) || ok=0
  [ "$ok" -ge 3 ] && break
  sleep 0.2
done
echo "  $(date -u +%T) three 200 in a row after ${t} s"
