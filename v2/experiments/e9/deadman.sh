#!/usr/bin/env bash
# A4 (E9, chapter 10; evidence/e9/alerting-prediction.md): the node that runs Prometheus and
# Alertmanager is frozen - only the dead man's switch outside the cluster can tell.
#   bash v2/experiments/e9/deadman.sh > v2/evidence/e9/a4-deadman.log
# Refuses to run if the PostgreSQL primary is on that node (chapter 8: freezing the primary's node
# ends in a failover and a split brain). The node is unpaused 270 s after the pause at the latest -
# before the pods on a NotReady node are evicted (taint tolerations of 300 s) - and by the trap.
set -uo pipefail
now() { date -u +%T.%3N; }
NODE=$(kubectl -n monitoring get pod alertmanager-kps-alertmanager-0 -o jsonpath='{.spec.nodeName}')
PROM=$(kubectl -n monitoring get pod prometheus-kps-prometheus-0 -o jsonpath='{.spec.nodeName}')
PRIMARY=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')
PNODE=$(kubectl -n data get pod "$PRIMARY" -o jsonpath='{.spec.nodeName}')
echo "== $(now) Alertmanager on $NODE, Prometheus on $PROM, PostgreSQL primary $PRIMARY on $PNODE"
[ "$PNODE" = "$NODE" ] && { echo "refused: the primary is on $NODE"; exit 1; }
last_hb() { docker exec alert-bridge python -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:9095/state'))['last_heartbeat'])"; }
write() { kubectl -n data exec "$PRIMARY" -c postgres -- psql -qtAX -d postgres -c "CREATE TABLE IF NOT EXISTS e9_deadman (t timestamptz); INSERT INTO e9_deadman VALUES (now()) RETURNING to_char(t, 'HH24:MI:SS')" 2>&1 | head -1; }
T0=$(date -u +%FT%TZ)
trap 'docker unpause "$NODE" >/dev/null 2>&1' EXIT
echo "== $(now) last heartbeat before the pause: $(date -u -d @"$(last_hb)" +%T.%3N); a write: $(write)"
docker pause "$NODE" >/dev/null; TP=$(date +%s); echo "== $(now) docker pause $NODE"
opened=
while [ $(( $(date +%s) - TP )) -lt 270 ]; do
  sleep 15
  e=$(docker logs --since "$T0" alert-bridge 2>&1 | grep -o '"event": "deadman_opened", "iid": [0-9]*, "silent_seconds": [0-9.]*')
  echo "  $(now) +$(( $(date +%s) - TP ))s node $(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}') | write: $(write) ${e:+| bridge: $e}"
  [ -n "$e" ] && [ -z "$opened" ] && opened=$(date +%s)
  [ -n "$opened" ] && [ $(( $(date +%s) - opened )) -ge 30 ] && break
done
docker unpause "$NODE" >/dev/null; TU=$(date +%s); echo "== $(now) docker unpause $NODE (+$((TU - TP)) s)"
for i in $(seq 1 24); do
  sleep 10
  c=$(docker logs --since "$T0" alert-bridge 2>&1 | grep -o '"event": "deadman_closed", "iid": [0-9]*')
  [ -n "$c" ] && { echo "  $(now) +$(( $(date +%s) - TU ))s after the unpause: $c"; break; }
done
echo "== $(now) node $(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'), Prometheus targets up: $(kubectl get --raw /api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query?query=count%28up%3D%3D1%29 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["result"][0]["value"][1])')"
echo "== bridge events since $T0:"; docker logs --since "$T0" alert-bridge 2>&1 | grep -v '"heartbeat' | cut -c1-220 | sed 's/^/  /'
