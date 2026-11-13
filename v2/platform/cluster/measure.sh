#!/usr/bin/env bash
# Resource snapshot of the machine and the "ent" cluster, layer by layer (E0 and later phases).
#   bash v2/platform/cluster/measure.sh [label]
# Layers: WSL VM -> Docker containers -> node cgroups (what the kernel enforces)
#         -> kubelet view (capacity, allocatable, eviction signal) -> pods (metrics-server).
set -uo pipefail
label=${1:-snapshot}
echo "## $label  $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo; echo "### 1. WSL VM"
free -m
echo "PSI memory: $(head -1 /proc/pressure/memory)"
echo "PSI cpu:    $(head -1 /proc/pressure/cpu)"
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)"

echo; echo "### 2. containers (docker stats: usage excludes inactive page cache)"
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' | sort

nodes=$(kind get nodes --name ent 2>/dev/null | sort)
[ -n "$nodes" ] || { echo "no ent cluster"; exit 0; }

echo; echo "### 3. node cgroups (kernel limits and usage)"
printf '%-18s %-8s %-10s %-11s %-11s %-12s %s\n' node cpuset cpu.max mem.max_MiB current_MiB workingset_MiB oom_kill
for n in $nodes; do
  docker exec "$n" sh -c '
    cg=/sys/fs/cgroup
    max=$(cat $cg/memory.max); [ "$max" = max ] || max=$((max/1048576))
    cur=$(( $(cat $cg/memory.current)/1048576 ))
    inact=$(awk "/^inactive_file /{print \$2}" $cg/memory.stat)
    ws=$(( ($(cat $cg/memory.current)-inact)/1048576 ))
    oom=$(awk "/^oom_kill /{print \$2}" $cg/memory.events)
    printf "%-18s %-8s %-10s %-11s %-11s %-12s %s\n" "$(hostname)" "$(cat $cg/cpuset.cpus.effective)" \
      "$(cut -d" " -f1 $cg/cpu.max)" "$max" "$cur" "$ws" "$oom"'
done

echo; echo "### 4. kubelet view: capacity, allocatable, eviction signal"
kubectl get nodes -o custom-columns='NODE:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone,CAP_CPU:.status.capacity.cpu,ALLOC_CPU:.status.allocatable.cpu,CAP_MEM:.status.capacity.memory,ALLOC_MEM:.status.allocatable.memory,PODS:.status.allocatable.pods'
for n in $nodes; do
  kubectl get --raw "/api/v1/nodes/$n/proxy/stats/summary" 2>/dev/null |
    jq -r --arg n "$n" '.node.memory as $m | "\($n): workingSet=\(($m.workingSetBytes/1048576)|floor) MiB, available=\(($m.availableBytes/1048576)|floor) MiB (signal memory.available)"'
done

echo; echo "### 5. requests vs allocatable (what the scheduler sees)"
kubectl describe nodes 2>/dev/null | awk '/^Name:/{n=$2} /Allocated resources:/{f=1} f&&/^  (cpu|memory) /{print n": "$0} /^Events:/{f=0}'

echo; echo "### 6. pods (metrics-server, working set)"
kubectl top nodes 2>/dev/null || echo "(metrics-server not ready)"
kubectl top pods -A --sort-by=memory 2>/dev/null | head -25
