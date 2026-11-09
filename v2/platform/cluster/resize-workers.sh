#!/usr/bin/env bash
# Change the memory size of the running workers without recreating the cluster (E7: 3072 -> 3584 MiB,
# capacity for the backup stack, chapter 8). Same derivation as create.sh:
#   eviction-hard memory.available < MemTotal - (size - 150 MiB)
# Order matters: when growing, the cgroup limit (docker update) is raised before kubelet's threshold,
# when shrinking it is lowered after it - kubelet must never believe in memory the kernel will not
# give. kubelet restarts, the pods keep running.
#   bash v2/platform/cluster/resize-workers.sh 3584
set -euo pipefail
NEW=${1:?size in MiB}; MARGIN=150
MEMTOTAL_MI=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
EVICT_MI=$((MEMTOTAL_MI - NEW + MARGIN))
TYPE="sim-4c$(awk -v m="$NEW" 'BEGIN {printf "%g", m / 1024}')g"     # 3584 -> sim-4c3.5g
for n in ent-worker ent-worker2 ent-worker3; do
  old=$(( $(docker inspect -f '{{.HostConfig.Memory}}' "$n") / 1048576 ))
  [ "$NEW" -ge "$old" ] && docker update --memory "${NEW}m" --memory-swap "${NEW}m" "$n" >/dev/null
  docker exec "$n" sed -i -E \
    -e "s/memory\.available<[0-9]+Mi/memory.available<${EVICT_MI}Mi/" \
    -e "s/instance-type=sim-[^,\" ]*/instance-type=${TYPE}/" /var/lib/kubelet/kubeadm-flags.env
  docker exec "$n" systemctl restart kubelet
  sleep 5
  kubectl wait --for=condition=Ready "node/$n" --timeout=120s >/dev/null
  [ "$NEW" -lt "$old" ] && docker update --memory "${NEW}m" --memory-swap "${NEW}m" "$n" >/dev/null
  kubectl label node "$n" "node.kubernetes.io/instance-type=${TYPE}" --overwrite >/dev/null
  echo "$n: ${old} -> ${NEW} MiB (cgroup $(docker exec "$n" cat /sys/fs/cgroup/memory.max)), eviction memory.available<${EVICT_MI}Mi, allocatable $(kubectl get node "$n" -o jsonpath='{.status.allocatable.memory}'), $TYPE"
done
