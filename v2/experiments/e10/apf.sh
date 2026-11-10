#!/usr/bin/env bash
# K5 (E10, chapter 11): API Priority and Fairness against one flooding client, in the kwok cluster.
#   bash v2/experiments/e10/apf.sh <kubeconfig> <out-dir>      (called by scale.sh apf)
# e10-flood: FlowSchema -> priority level e10-low (1 concurrency share, nothing lent, one queue of 5),
#            40 workers LIST all pods (resourceVersion=0) for 60 s.
# e10-victim: default flow schemas (service accounts -> workload-low), GETs one pod every 0.5 s - 30 s
#            alone, then during the flood.
# Tokens are short-lived (1 h, a throwaway cluster) and go to curl through a header file, not argv.
set -uo pipefail
KC=$1; OUT=$2; K="kubectl --kubeconfig $KC"
SERVER=$($K config view --minify -o jsonpath='{.clusters[0].cluster.server}')
now() { date -u +%T; }
$K apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: e10-flood, namespace: default}
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: e10-victim, namespace: default}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: e10-read-pods}
rules: [{apiGroups: [""], resources: [pods], verbs: [get, list]}]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: e10-read-pods}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: e10-read-pods}
subjects:
  - {kind: ServiceAccount, name: e10-flood, namespace: default}
  - {kind: ServiceAccount, name: e10-victim, namespace: default}
---
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: PriorityLevelConfiguration
metadata: {name: e10-low}
spec:
  type: Limited
  limited:
    nominalConcurrencyShares: 1
    lendablePercent: 0
    limitResponse:
      type: Queue
      queuing: {queues: 1, handSize: 1, queueLengthLimit: 5}
---
apiVersion: flowcontrol.apiserver.k8s.io/v1
kind: FlowSchema
metadata: {name: e10-flood}
spec:
  priorityLevelConfiguration: {name: e10-low}
  matchingPrecedence: 500
  distinguisherMethod: {type: ByUser}
  rules:
    - subjects: [{kind: ServiceAccount, serviceAccount: {name: e10-flood, namespace: default}}]
      resourceRules: [{verbs: ["*"], apiGroups: ["*"], resources: ["*"], namespaces: ["*"], clusterScope: true}]
EOF
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
( umask 077
  printf 'Authorization: Bearer %s\n' "$($K create token e10-flood -n default --duration 1h)" > "$tmp/flood.hdr"
  printf 'Authorization: Bearer %s\n' "$($K create token e10-victim -n default --duration 1h)" > "$tmp/victim.hdr" )
POD=$($K get pods -o jsonpath='{.items[0].metadata.name}')
metric() { $K get --raw /metrics | grep -E "^apiserver_flowcontrol_rejected_requests_total\{.*priority_level=\"$1\"" | awk '{s += $2} END {print s + 0}'; }
victim() {  # $1 seconds -> "<http code> <seconds>" per line
  local end=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    curl -sk -o /dev/null -w '%{http_code} %{time_total}\n' -H @"$tmp/victim.hdr" "$SERVER/api/v1/namespaces/default/pods/$POD"
    sleep 0.5
  done
}
# which flow schema and priority level a response went through (APF sets these headers on every response)
pf() {  # $1 header file -> "<status> flow schema <name>, priority level <name>"
  local fs pl; fs=$(grep -i '^X-Kubernetes-PF-FlowSchema-UID' "$1" | tr -d '\r' | awk '{print $2}')
  pl=$(grep -i '^X-Kubernetes-PF-PriorityLevel-UID' "$1" | tr -d '\r' | awk '{print $2}')
  echo "$(head -1 "$1" | tr -d '\r'): flow schema $($K get flowschemas -o jsonpath="{.items[?(@.metadata.uid=='$fs')].metadata.name}"), priority level $($K get prioritylevelconfigurations -o jsonpath="{.items[?(@.metadata.uid=='$pl')].metadata.name}")"
}
# incident E10-1 re-run: the cluster of K2 (--disable-qps-limits) runs without APF - check, do not assume
echo "  API server flags: $(docker inspect kwok-scale-kube-apiserver --format '{{json .Args}}' | tr ',' '\n' | grep -E 'inflight|priority-and-fairness' | tr -d '"[]' | tr '\n' ' ')"
echo "== $(now) K5: victim alone for 30 s"
curl -sk -o /dev/null -D "$tmp/v.hdr" -H @"$tmp/victim.hdr" "$SERVER/api/v1/namespaces/default/pods/$POD"
echo "  victim's GET: $(pf "$tmp/v.hdr")"
# K5 run 5: the API server's memory (its cgroup) every second, from about 10 s before the flood until
# 5 s after it; 0 while the container is down
CG=/sys/fs/cgroup/system.slice/docker-$(docker inspect -f '{{.Id}}' kwok-scale-kube-apiserver).scope
FLOOD_AT=$(( $(date +%s) + 30 ))
( sleep 20; T0=$(date +%s.%N); echo "t_s memory_current_MiB anon_MiB (t=0 about 10 s before the flood)"
  while [ "$(date +%s)" -lt "$(( FLOOD_AT + 65 ))" ]; do
    echo "$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN {printf "%.1f", a - b}') $(( $(cat "$CG/memory.current" 2>/dev/null || echo 0) / 1048576 )) $(( $(awk '/^anon / {print $2}' "$CG/memory.stat" 2>/dev/null || echo 0) / 1048576 ))"
    sleep 1
  done > "$OUT/apf-apiserver-mem.txt" ) &
sampler=$!
victim 30 > "$OUT/apf-victim-quiet.txt"
echo "  nominal seats: $($K get --raw /metrics | grep -E '^apiserver_flowcontrol_nominal_limit_seats[{]priority_level="(e10-low|workload-low)"' | sed -E 's/.*priority_level="([^"]+)"[}] /\1=/' | tr '\n' ' ')"
r0=$(metric e10-low); w0=$(metric workload-low)
( sleep 20; curl -sk -m 90 -D "$tmp/probe.hdr" -o "$tmp/probe.body" -H @"$tmp/flood.hdr" "$SERVER/api/v1/pods?resourceVersion=0"
  if [ -s "$tmp/probe.hdr" ]; then
    echo "  $(now) a flood request 20 s in: $(pf "$tmp/probe.hdr")"
    [ "$(stat -c %s "$tmp/probe.body")" -lt 4096 ] && echo "    body: $(tr -s ' \n' '  ' < "$tmp/probe.body")"
  else echo "  $(now) a flood request 20 s in: no answer (connection failed)"; fi ) &
probe=$!
echo "== $(now) flood: ${WORKERS:-40} workers LIST all pods for 60 s; the victim keeps going"
END=$(( $(date +%s) + 60 ))
pids=()
for w in $(seq 1 ${WORKERS:-40}); do
  ( while [ "$(date +%s)" -lt "$END" ]; do
      r=$(curl -sk -m 90 -o "$tmp/body-$w" -w '%{http_code} %{time_total}' -H @"$tmp/flood.hdr" "$SERVER/api/v1/pods?resourceVersion=0")
      # K5 run 3: a 429 says who refused - APF ("Too many requests...") or the watch cache ("storage is
      # (re)initializing" after a restart); keep the message, spaces as _
      # (run 4: APF's 429 is not a JSON Status - keep the start of the plain text instead)
      case $r in 429*) m=$(grep -o '"message": *"[^"]*"' "$tmp/body-$w" | head -1 | sed 's/"message": *//')
                       [ -z "$m" ] && m="text:$(head -c 48 "$tmp/body-$w")"
                       echo "$r $(printf '%s' "$m" | tr -s ' \n"' '___')" ;; *) echo "$r" ;; esac
    done > "$tmp/flood-$w.txt" ) &
  pids+=($!)
done
# incident E10-1: the flood stops itself when the VM runs short of memory
( while [ "$(date +%s)" -lt "$END" ]; do
    a=$(free -m | awk '/^Mem:/ {print $7}')
    if [ "$a" -lt 1200 ]; then
      echo "$(now) memory guard: $a MiB available - flood stopped" | tee "$OUT/apf-guard.txt"
      for p in "${pids[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
      break
    fi
    sleep 2
  done ) &
guard=$!
victim 60 > "$OUT/apf-victim-flood.txt"
wait "${pids[@]}" 2>/dev/null; kill "$guard" 2>/dev/null; wait "$guard" 2>/dev/null; wait "$probe" "$sampler" 2>/dev/null
cat "$tmp"/flood-*.txt > "$OUT/apf-flood.txt"
echo "== $(now) rejected by APF (apiserver_flowcontrol_rejected_requests_total): e10-low +$(( $(metric e10-low) - r0 )), workload-low +$(( $(metric workload-low) - w0 ))"
$K get --raw /metrics | grep -E '^apiserver_flowcontrol_rejected_requests_total[{].*priority_level="(e10-low|workload-low)"' | sed 's/^/  /'
python3 - "$OUT" <<'PY'
import collections, statistics, sys
d = sys.argv[1]
def load(name):  # "<code> <seconds> [<message of a 429>]"
    rows = [l.split() for l in open(f"{d}/{name}") if l.strip()]
    return [(p[0], float(p[1]), p[2] if len(p) > 2 else "") for p in rows if len(p) >= 2]
def pct(xs, q):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else float("nan")
flood = load("apf-flood.txt")
codes = collections.Counter(c for c, _, _ in flood)
ok = [t for c, t, _ in flood if c == "200"]
print(f"  flood: {len(flood)} requests, codes {dict(codes)}; LIST p50 {pct(ok, .5):.2f} s, p99 {pct(ok, .99):.2f} s (200 only)")
why = collections.Counter(m for c, _, m in flood if c == "429")
if any(why):
    print(f"  429 by message: {dict(why)}")
for name in ("apf-victim-quiet.txt", "apf-victim-flood.txt"):
    v = load(name); ts = [t * 1000 for c, t, _ in v if c == "200"]
    print(f"  victim {name[11:-4]:5}: {len(v)} GETs, codes {dict(collections.Counter(c for c, _, _ in v))}; p50 {pct(ts, .5):.1f} ms, p99 {pct(ts, .99):.1f} ms")
PY
