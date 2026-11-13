#!/usr/bin/env bash
# K3 (E10, chapter 11): what etcd keeps per pod, and what deleting, compacting and defragmenting do to it.
#   bash v2/experiments/e10/etcd-size.sh up      (kwok cluster "scale" up, its pods deleted: scale.sh clean)
#   bash v2/experiments/e10/etcd-size.sh down    (10 000 pods there)
# up:   1. wait for the API server's own compaction (every 5 min, to the revision of its previous run),
#          defragment: the baseline without pods
#       2. 5000, then 10 000 [虚拟] pods: size with their history, then compacted and defragmented
# down: 10 000 -> 5000 -> 0 pods, compacted and defragmented at each step: the live bytes per pod
# Sizes straight from etcd (endpoint status), not from Prometheus. etcdctl gets 120 s: its default of 5 s
# is too short for defragmenting 170 MiB (first attempt, k3-clean.log). "compact --physical" waits until
# the old revisions are really gone - without it (the "up" run of 10:26) the defragmentation that follows
# still copies them.
set -uo pipefail
MODE=${1:?up|down}
K="kubectl --kubeconfig $HOME/.kwok/scale.kubeconfig"; E=kwok-scale-etcd
now() { date -u +%T; }
ec() { docker exec "$E" etcdctl --endpoints=127.0.0.1:2379 --command-timeout=120s "$@"; }
st() { ec endpoint status -w json | python3 -c 'import json,sys; s = json.load(sys.stdin)[0]["Status"]; print(s["header"]["revision"], round(s["dbSize"] / 1048576, 2), round(s["dbSizeInUse"] / 1048576, 2))'; }
show() { local r s u; read -r r s u <<< "$(st)"; echo "  $(now) $1: revision $r, db size $s MiB, in use $u MiB; pods $($K get pods -o name | wc -l), events $($K get events -A -o name | wc -l); available MiB $(free -m | awk '/^Mem:/ {print $7}')"; }
guard() { [ "$(free -m | awk '/^Mem:/ {print $7}')" -lt 800 ] && { echo "ABORT: less than 800 MiB available"; exit 2; }; }
compact() { local rev; rev=$(st | cut -d' ' -f1); echo "  $(now) compact --physical to revision $rev: $(ec compact --physical "$rev" 2>&1 | tail -1)"
            echo "  $(now) defragmentation: $(ec defrag 2>&1 | tail -1)"; }
pods_to() {  # $1 = the number of pods to wait for
  for i in $(seq 1 120); do [ "$($K get pods -o name | wc -l)" -eq "$1" ] && break; guard; sleep 5; done; }
case $MODE in
up)
  echo "== $(now) 1. no pods: the API server's compaction, then defragmentation"
  show "start"
  read -r r0 s0 u0 <<< "$(st)"; T0=$(date +%s)
  while :; do
    sleep 15; read -r r s u <<< "$(st)"
    python3 -c "import sys; sys.exit(0 if $u < 0.8 * $u0 else 1)" && break
    [ $(( $(date +%s) - T0 )) -gt 720 ] && { echo "  no compaction within 12 min"; break; }
  done
  show "after the API server's compaction, $(( $(date +%s) - T0 )) s later"
  echo "  $(now) defragmentation: $(ec defrag 2>&1 | tail -1)"; show "after defragmentation"
  prev=0
  for n in 5000 10000; do
    guard; tmp=$(mktemp -d)
    python3 - "$tmp" "$prev" "$n" <<'PY'
import json, sys
d, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
for k in range(8):
    items = [{"apiVersion": "v1", "kind": "Pod",
              "metadata": {"name": f"p-{i:05d}", "namespace": "default", "labels": {"app": "e10"}},
              "spec": {"containers": [{"name": "c", "image": "registry.k8s.io/pause:3.10",
                                       "resources": {"requests": {"cpu": "100m", "memory": "128Mi"}}}],
                       "tolerations": [{"operator": "Exists"}]}} for i in range(a + k, b, 8)]
    json.dump({"apiVersion": "v1", "kind": "List", "items": items}, open(f"{d}/chunk-{k}.json", "w"))
PY
    echo "== $(now) 2. pods $prev -> $n"
    for k in 0 1 2 3 4 5 6 7; do $K create -f "$tmp/chunk-$k.json" >/dev/null 2>&1 & done; wait; rm -rf "$tmp"
    for i in $(seq 1 120); do [ "$($K get pods -o name --field-selector status.phase=Running | wc -l)" -ge "$n" ] && break; guard; sleep 5; done
    show "$n pods Running"
    compact; show "$n pods, compacted and defragmented"
    prev=$n
  done ;;
down)
  echo "== $(now) 3. down: compacted and defragmented at the start, at 5000 and at 0 pods"
  show "start"; compact; show "compacted and defragmented"
  # kubectl deletes named pods one after the other at about 5/s (run of 10:33: 2866 in about 590 s,
  # stopped by its timeout): 16 kubectl in parallel
  $K get pods -o name | grep -E '^pod/p-0[5-9]' | xargs -r -P 16 -n 100 $K delete --wait=false >/dev/null 2>&1
  pods_to 5000
  show "5000 pods left (the deletions are new revisions)"; compact; show "5000 pods, compacted and defragmented"
  $K delete pods --all --wait=false >/dev/null 2>&1; pods_to 0
  show "0 pods"; compact; show "0 pods, compacted and defragmented" ;;
esac
