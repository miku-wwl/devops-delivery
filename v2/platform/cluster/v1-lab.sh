#!/usr/bin/env bash
# Pause or resume the v1 "lab" Kind cluster to free memory for v2 (reversible; no state is lost:
# the node containers keep their filesystems, etcd data and images).
#   bash v2/platform/cluster/v1-lab.sh stop|start|status
# GitLab, gitlab-runner and kind-registry are shared with v2 and are not touched.
set -euo pipefail
nodes=(lab-control-plane lab-worker lab-worker2)
# The node image stops on SIGRTMIN+3 (systemd's shutdown signal); systemd then stops kubelet,
# containerd and every pod, which takes longer than Docker's default 10 s before SIGKILL.
# Kind creates node containers with --restart=on-failure:1, and a manual "docker stop" only
# suspends a restart policy until the Docker daemon restarts. After a WSL reboot the paused v1
# nodes (systemd exits with 130) came back on their own, so "stop" also removes the policy and
# "start" restores it.
case "${1:-status}" in
  stop)   docker update --restart=no "${nodes[@]}" >/dev/null
          docker stop -t 120 "${nodes[@]}" ;;
  start)  docker update --restart=on-failure:1 "${nodes[@]}" >/dev/null
          docker start "${nodes[0]}" && sleep 5 && docker start "${nodes[@]:1}"
          # right after start the API server answers before its RBAC caches are ready
          # ("Forbidden: unknown"), so wait for /readyz before waiting for the nodes
          for _ in $(seq 60); do kubectl --context kind-lab get --raw /readyz >/dev/null 2>&1 && break; sleep 3; done
          kubectl --context kind-lab wait --for=condition=Ready nodes --all --timeout=180s ;;
  status) docker ps -a --filter 'name=^lab-' --format '{{.Names}}\t{{.Status}}' ;;
  *) echo "usage: $0 stop|start|status" >&2; exit 2 ;;
esac
