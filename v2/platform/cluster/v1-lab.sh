#!/usr/bin/env bash
# Pause or resume the v1 "lab" Kind cluster to free memory for v2 (reversible; no state is lost:
# the node containers keep their filesystems, etcd data and images).
#   bash v2/platform/cluster/v1-lab.sh stop|start|status
# GitLab, gitlab-runner and kind-registry are shared with v2 and are not touched.
set -euo pipefail
nodes=(lab-control-plane lab-worker lab-worker2)
# The node image stops on SIGRTMIN+3 (systemd's shutdown signal); systemd then stops kubelet,
# containerd and every pod, which takes longer than Docker's default 10 s before SIGKILL.
case "${1:-status}" in
  stop)   docker stop -t 120 "${nodes[@]}" ;;
  start)  docker start "${nodes[0]}" && sleep 5 && docker start "${nodes[@]:1}"
          # right after start the API server answers before its RBAC caches are ready
          # ("Forbidden: unknown"), so wait for /readyz before waiting for the nodes
          for _ in $(seq 60); do kubectl --context kind-lab get --raw /readyz >/dev/null 2>&1 && break; sleep 3; done
          kubectl --context kind-lab wait --for=condition=Ready nodes --all --timeout=180s ;;
  status) docker ps -a --filter 'name=^lab-' --format '{{.Names}}\t{{.Status}}' ;;
  *) echo "usage: $0 stop|start|status" >&2; exit 2 ;;
esac
