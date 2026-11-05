#!/usr/bin/env bash
# Smoke-test the devops-lab environment (run as the lab user, not root).
#   bash automation/lab/verify.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source <(tr -d '\r' < "$HERE/versions.env")

echo "== OS / systemd =="
grep PRETTY_NAME /etc/os-release
echo "systemd: $(ps -p 1 -o comm=)"
echo "docker service: $(systemctl is-active docker)"

echo "== client versions =="
docker version --format 'docker client {{.Client.Version}} / server {{.Server.Version}}'
docker compose version
kubectl version --client | head -1
kind version
helm version --short
argocd version --client --short
kubectl argo rollouts version --short
trivy --version | head -1
syft version | sed -n '2p'
cosign version 2>&1 | grep -E '^GitVersion'
k6 version | head -1
yq --version

echo "== docker run hello-world =="
docker run --rm hello-world | sed -n '2p'

echo "== kind smoke cluster =="
kind create cluster --name smoke --image "$KIND_NODE_IMAGE" --wait 180s
kubectl get nodes -o wide
kubectl get pods -A
kind delete cluster --name smoke
echo "SMOKE TEST PASSED"
