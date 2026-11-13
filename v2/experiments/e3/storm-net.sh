#!/usr/bin/env bash
# Is the slow pod -> database path during the load-balancer crash loop a network problem?
#   bash v2/experiments/e3/storm-net.sh <label> [rate] [seconds]
# Kernel counters (interface drops, TCP retransmissions and timeouts, socket-level drops) of the
# worker nodes and of four pods (catalog and gateway on ent-worker, PostgreSQL primary and Valkey
# on ent-worker3), before and after lb-storm.sh, and two probes during the run: a TCP connect to
# PostgreSQL from the root network namespace of ent-worker (no ztunnel on that path) and
# probe_db.py from inside the catalog pod on ent-worker (through ztunnel). Nothing is changed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; RATE=${2:-180}; SECS=${3:-40}
OUT="$ROOT/v2/evidence/e3/$LABEL"; mkdir -p "$OUT"
DUR=$((SECS + 45))
COUNTERS="TcpRetransSegs TcpExtTCPTimeouts TcpExtTCPSynRetrans TcpExtTCPLossProbes TcpExtTCPAbortOnTimeout
  TcpExtTCPBacklogDrop TcpExtListenDrops TcpExtListenOverflows TcpExtTCPRcvQDrop IpInDiscards IpExtInNoRoutes"
COUNTERS=$(echo $COUNTERS)
pod_on() { kubectl -n "$1" get pods --no-headers -o custom-columns=N:.metadata.name,NODE:.spec.nodeName |
  awk -v p="$2" -v n="$3" '$1 ~ "^" p && $2 == n {print $1; exit}'; }
pid_of() { docker exec "$1" sh -c "crictl inspect \$(crictl ps --name '$3' -o json | jq -r \
  '.containers[] | select(.labels[\"io.kubernetes.pod.name\"] == \"$2\") | .id' | head -1) | jq .info.pid"; }
TARGETS=()
for t in "storefront catalog- ent-worker app" "storefront gateway- ent-worker app" \
         "data pg-main ent-worker3 postgres" "data valkey ent-worker3 valkey"; do
  set -- $t
  pod=$(pod_on "$1" "$2" "$3"); [ -n "$pod" ] || continue
  pid=$(pid_of "$3" "$pod" "$4"); TARGETS+=("$3 $pod $pid")
  echo "pod network namespace: $pod on $3 (pid $pid)"
done
PG_IP=$(kubectl -n data get pod "$(pod_on data pg-main ent-worker3)" -o jsonpath='{.status.podIP}')
snapshot() {
  for n in ent-worker ent-worker2 ent-worker3; do
    docker exec "$n" sh -c "ip -s link show eth0 | awk 'NR==4 {print \"eth0_rx_dropped\", \$4} NR==6 {print \"eth0_tx_dropped\", \$4}';
      nstat -asz $COUNTERS | awk 'NR > 1 {print \$1, \$2}'" | sed "s/^/node:$n /"
  done
  for t in "${TARGETS[@]}"; do
    set -- $t
    docker exec "$1" nsenter -t "$3" -n nstat -asz $COUNTERS | awk -v p="$2" 'NR > 1 {print "pod:" p, $1, $2}'
  done
}
snapshot > "$OUT/counters-before.txt"
catalog=$(pod_on storefront catalog- ent-worker)
docker exec ent-worker timeout "$DUR" bash -c "while true; do s=\$(date +%s%N)
    if timeout 3 bash -c 'exec 3<>/dev/tcp/$PG_IP/5432' 2>/dev/null; then r=\$(( (\$(date +%s%N) - s) / 1000000 )); else r=fail; fi
    echo \"\$(date -u +%T) node_connect_ms=\$r\"; sleep 0.5; done" > "$OUT/node-to-pg.log" 2>&1 &
p1=$!
kubectl -n storefront exec -i "$catalog" -c app -- python - "$DUR" < "$HERE/probe_db.py" > "$OUT/pod-to-pg.log" 2>&1 &
p2=$!
sleep 10
bash "$HERE/lb-storm.sh" "$LABEL" "$RATE" "$SECS" > "$OUT/lb-storm.txt" 2>&1
snapshot > "$OUT/counters-after.txt"
wait $p1 $p2 2>/dev/null
grep -E '^(envoy crashes|rate=|requests=)' "$OUT/lb-storm.txt"
echo "counter changes during the run (non-zero only):"
awk 'NR == FNR {b[$1" "$2] = $3; next} {d = $3 - b[$1" "$2]; if (d != 0) printf "  %-34s %-26s %+d\n", $1, $2, d}' \
  "$OUT/counters-before.txt" "$OUT/counters-after.txt"
echo "probes, max per 5 s (ms; fail = no TCP connection within 3 s):"
cat "$OUT/node-to-pg.log" "$OUT/pod-to-pg.log" | awk '
  { split($1, t, ":"); b = sprintf("%s:%s:%02d", t[1], t[2], int(t[3] / 5) * 5); seen[b] = 1
    for (i = 2; i <= NF; i++) { split($i, kv, "="); k = kv[1]; v = kv[2]
      if (v == "fail" || k ~ /_failed$/) { f[b, k]++; continue }
      if (v + 0 > m[b, k]) m[b, k] = v + 0 } }
  END { for (b in seen) printf "%s  node->pg connect %5.0f%s | pod->pg query %5.0f%s | pod->pg connect %5.0f%s\n", b,
    m[b, "node_connect_ms"], (f[b, "node_connect_ms"] ? " (" f[b, "node_connect_ms"] " fail)" : ""),
    m[b, "query_ms"], (f[b, "query_failed"] ? " (" f[b, "query_failed"] " fail)" : ""),
    m[b, "connect_ms"], (f[b, "connect_failed"] ? " (" f[b, "connect_failed"] " fail)" : "") }' | sort
