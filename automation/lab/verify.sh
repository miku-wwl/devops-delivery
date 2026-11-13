#!/usr/bin/env bash
# Smoke-test the devops-lab environment (run as the lab user, not root).
#   bash automation/lab/verify.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source <(tr -d '\r' < "$HERE/versions.env")

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== OS / systemd =="
grep PRETTY_NAME /etc/os-release
# A failing command inside $(...) does not stop the script under set -e when its output is
# only echoed, so the conditions are asserted explicitly.
pid1="$(ps -p 1 -o comm=)"; echo "systemd: $pid1"
[ "$pid1" = systemd ] || fail "PID 1 is '$pid1', not systemd - check [boot] systemd=true in /etc/wsl.conf"
docker_state="$(systemctl is-active docker || true)"; echo "docker service: $docker_state"
[ "$docker_state" = active ] || fail "docker service is '$docker_state'"

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
trap 'kind delete cluster --name smoke >/dev/null 2>&1 || true' EXIT   # also clean up after a failure
kind create cluster --name smoke --image "$KIND_NODE_IMAGE" --wait 180s
kubectl get nodes -o wide
kubectl get pods -A
kind delete cluster --name smoke
echo "SMOKE TEST PASSED"
