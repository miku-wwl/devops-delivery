#!/usr/bin/env bash
# E10 (chapter 11): a real control plane under virtual load (hypotheses in evidence/e10/scale-prediction.md).
# kwokctl cluster "scale": etcd, kube-apiserver, kube-controller-manager, kube-scheduler (v1.37.0) and the
# kwok controller as Docker containers, with a Prometheus scraping them. Nodes and pods are [虚拟].
#   bash v2/experiments/e10/scale.sh up <run> [--disable-qps-limits]   # cluster + 1000 nodes
#   bash v2/experiments/e10/scale.sh pods <run> <n>                    # n pods, 8 parallel creators, timeline
#   bash v2/experiments/e10/scale.sh state <run> <label>               # etcd size, objects, memory
#   bash v2/experiments/e10/scale.sh lists <run>                       # LIST latency and where it is served from
#   bash v2/experiments/e10/scale.sh apf <run>                         # one flooding client against APF
#   bash v2/experiments/e10/scale.sh clean <run>                       # delete the pods, etcd size, defrag
#   bash v2/experiments/e10/scale.sh down
# Its own kubeconfig (~/.kwok/scale.kubeconfig): the lab's current context stays kind-ent. Aborts when
# the WSL VM has less than 800 MiB available - the lab cluster shares the machine.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
NAME=scale; KC=$HOME/.kwok/scale.kubeconfig; K="kubectl --kubeconfig $KC"; PROM=http://127.0.0.1:19090
CMD=${1:?up|pods|state|lists|apf|clean|down}; RUN=${2:-}
OUT="$ROOT/v2/evidence/e10/$RUN"; [ -n "$RUN" ] && mkdir -p "$OUT"
now() { date -u +%T; }
guard() { local a; a=$(free -m | awk '/^Mem:/ {print $7}'); [ "$a" -lt 800 ] && { echo "ABORT: only $a MiB available"; exit 2; }; echo "$a"; }
pq() { curl -s "$PROM/api/v1/query" --data-urlencode "query=$1" | python3 -c '
import json, sys
r = json.load(sys.stdin)["data"]["result"]
print(" ".join((list(x["metric"].values())[-1] if len(r) > 1 and x["metric"] else "") + ("=" if len(r) > 1 and x["metric"] else "") + format(float(x["value"][1]), ".6g") for x in r) or "-")'; }
case $CMD in
up)
  shift 2
  mkdir -p "$HOME/.kwok"
  echo "== $(now) kwokctl create cluster (v1.37.0, Prometheus on 19090) $* - available MiB $(guard)"
  KWOK_KUBE_VERSION=v1.37.0 kwokctl create cluster --name $NAME --runtime docker --kubeconfig "$KC" \
    --prometheus-port 19090 --wait 10m "$@" 2>&1 | tail -3
  echo "  $(now) server: $($K version -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])'); lab context unchanged: $(kubectl config current-context)"
  t0=$(date +%s.%N); kwokctl scale node --name $NAME --replicas 1000 >/dev/null 2>&1; t1=$(date +%s.%N)
  for i in $(seq 1 60); do r=$($K get nodes --no-headers 2>/dev/null | grep -c " Ready"); [ "$r" -ge 1000 ] && break; sleep 2; done
  echo "  $(now) 1000 virtual nodes created in $(python3 -c "print(round($t1 - $t0, 1))") s, Ready: $r; available MiB $(guard)"
  $K get node -o jsonpath='{.items[0].metadata.name} {.items[0].status.capacity} taints={.items[0].spec.taints}{"\n"}' | sed 's/^/  example node: /' ;;
pods)
  N=${3:?n}; tmp=$(mktemp -d)
  python3 - "$tmp" "$N" <<'PY'
import json, sys
d, n = sys.argv[1], int(sys.argv[2])
for k in range(8):
    items = [{"apiVersion": "v1", "kind": "Pod",
              "metadata": {"name": f"p-{i:05d}", "namespace": "default", "labels": {"app": "e10"}},
              "spec": {"containers": [{"name": "c", "image": "registry.k8s.io/pause:3.10",
                                       "resources": {"requests": {"cpu": "100m", "memory": "128Mi"}}}],
                       "tolerations": [{"operator": "Exists"}]}} for i in range(k, n, 8)]
    json.dump({"apiVersion": "v1", "kind": "List", "items": items}, open(f"{d}/chunk-{k}.json", "w"))
PY
  count() { $K get pods -o name --field-selector "$1" 2>/dev/null | wc -l; }
  T0=$(date +%s.%N); echo "== $(now) creating $N pods with 8 parallel kubectl create - available MiB $(guard)"
  ( for k in 0 1 2 3 4 5 6 7; do $K create -f "$tmp/chunk-$k.json" >/dev/null 2>&1 & done; wait; date +%s.%N > "$tmp/created" ) &
  echo "t_s existing unscheduled running" > "$OUT/timeline.txt"
  while :; do
    t=$(python3 -c "print(round($(date +%s.%N) - $T0, 1))")
    all=$($K get pods -o name 2>/dev/null | wc -l); un=$(count spec.nodeName=); run=$(count status.phase=Running)
    echo "$t $all $un $run" >> "$OUT/timeline.txt"
    [ "$run" -ge "$N" ] && break
    [ "${t%.*}" -gt 1200 ] && { echo "  timeout"; break; }
    guard >/dev/null || break
    sleep 2
  done
  wait
  echo "  created all $N after $(python3 -c "print(round($(cat "$tmp/created") - $T0, 1))") s"
  python3 - "$OUT/timeline.txt" "$N" <<'PY'
import sys
rows = [list(map(float, l.split())) for l in open(sys.argv[1]).read().splitlines()[1:]]
n = int(sys.argv[2])
sched = [(t, all_ - un) for t, all_, un, run in rows]
done = next((t for t, s in sched if s >= n), None)
first = next((t for t, s in sched if s > 0), None)
best = max(((s2 - s1) / (t2 - t1) for (t1, s1), (t2, s2) in zip(sched, sched[5:]) if t2 > t1), default=0)
running = next((t for t, a, u, r in rows if r >= n), None)
print(f"  scheduled: first {first} s, all {n} at {done} s -> {n / (done - first):.0f} pods/s on average, best 10-s window {best:.0f} pods/s; all Running at {running} s")
PY
  echo "  scheduler (Prometheus): attempts by result $(pq 'sum by (result) (scheduler_schedule_attempts_total)')"
  rm -rf "$tmp" ;;
state)
  L=${3:?label}
  echo "== $(now) $L"
  echo "  etcd db size MiB: $(pq 'max(etcd_mvcc_db_total_size_in_bytes) / 1048576') (in use $(pq 'max(etcd_mvcc_db_total_size_in_use_in_bytes) / 1048576'))"
  echo "  objects: $(pq 'sum by (resource) (apiserver_resource_objects{resource=~"pods|nodes|leases|events"} or apiserver_storage_objects{resource=~"pods|nodes|leases.coordination.k8s.io|events"})')"
  echo "  resident memory MiB by component: $(pq 'sum by (job) (process_resident_memory_bytes) / 1048576')"
  docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' | grep "kwok-$NAME" | sed 's/^/  docker: /'
  echo "  WSL available MiB: $(free -m | awk '/^Mem:/ {print $7}')" ;;
lists)
  echo "== $(now) LIST of all pods, 5 times each (wall time, bytes), served from where"
  # where a LIST is served from (Kubernetes 1.37): apiserver_storage_list_total counts every LIST at the
  # storage layer, the watch cache's included; etcd sees a LIST only in etcd_request_duration_seconds
  m() { $K get --raw /metrics | grep -E "^$1" | awk '{s += $2} END {print s + 0}'; }
  e0=$(m 'etcd_request_duration_seconds_count[{]group="",operation="list",resource="pods"[}]')
  c0=$(m 'apiserver_watch_cache_consistent_read_total[{]fallback="false",group="",resource="pods"')
  for q in "resourceVersion=0" "" "limit=500"; do
    for i in 1 2 3 4 5; do
      s=$(date +%s.%N)
      if [ "$q" = limit=500 ]; then
        c=""; bytes=0; while :; do r=$($K get --raw "/api/v1/pods?limit=500${c:+&continue=$c}"); bytes=$((bytes + ${#r})); c=$(printf '%s' "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin)["metadata"].get("continue",""))'); [ -z "$c" ] && break; done
      else bytes=$($K get --raw "/api/v1/pods${q:+?$q}" | wc -c); fi
      echo "  ${q:-resourceVersion unset (consistent)} #$i: $(python3 -c "print(round($(date +%s.%N) - $s, 3))") s, $((bytes / 1048576)) MiB"
    done
  done
  echo "  LISTs of pods sent to etcd: +$(( $(m 'etcd_request_duration_seconds_count[{]group="",operation="list",resource="pods"[}]') - e0 )); consistent reads served by the watch cache: +$(( $(m 'apiserver_watch_cache_consistent_read_total[{]fallback="false",group="",resource="pods"') - c0 ))" ;;
apf)
  bash "$HERE/apf.sh" "$KC" "$OUT" ;;
clean)
  echo "== $(now) delete all pods"
  T0=$(date +%s); $K delete pods --all --wait=false >/dev/null 2>&1
  for i in $(seq 1 300); do n=$($K get pods -o name 2>/dev/null | wc -l); [ "$n" = 0 ] && break; sleep 2; done
  echo "  0 pods after $(( $(date +%s) - T0 )) s"
  sleep 35; bash "$0" state "$RUN" "after deleting the pods"
  E=$(docker ps --format '{{.Names}}' | grep "kwok-$NAME-etcd")
  echo "  $(now) defragmentation: $(docker exec "$E" etcdctl --endpoints=127.0.0.1:2379 defrag 2>&1 | tail -1)"
  sleep 35; echo "  etcd db size MiB after defrag: $(pq 'max(etcd_mvcc_db_total_size_in_bytes) / 1048576')" ;;
down)
  kwokctl delete cluster --name $NAME 2>&1 | tail -1; rm -f "$KC" ;;
esac
