#!/usr/bin/env bash
# Create the "lab" Kind cluster with a local OCI registry at localhost:5001.
# Follows the official kind guide "Local Registry" (kind.sigs.k8s.io/docs/user/local-registry/).
# Idempotent: re-running keeps an existing registry and cluster.
#   bash delivery/kind/create-lab-cluster.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source <(tr -d '\r' < "$ROOT/automation/lab/versions.env")
REG_NAME=kind-registry
REG_PORT=5001

# 1. registry container (Distribution / registry:3) on the host's loopback
if [ "$(docker inspect -f '{{.State.Running}}' "$REG_NAME" 2>/dev/null || true)" != "true" ]; then
  docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --network bridge \
    --name "$REG_NAME" registry:3.1.2
fi

# 2. cluster
if ! kind get clusters | grep -qx lab; then
  kind create cluster --config "$HERE/lab-cluster.yaml" --image "$KIND_NODE_IMAGE" --wait 180s
fi

# 3. tell containerd on every node that localhost:5001 means http://kind-registry:5000
for node in $(kind get nodes --name lab); do
  docker exec "$node" mkdir -p "/etc/containerd/certs.d/localhost:${REG_PORT}"
  printf '[host."http://%s:5000"]\n' "$REG_NAME" |
    docker exec -i "$node" cp /dev/stdin "/etc/containerd/certs.d/localhost:${REG_PORT}/hosts.toml"
done

# 4. put the registry on the kind network so nodes can resolve "kind-registry"
if [ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "$REG_NAME")" = "null" ]; then
  docker network connect kind "$REG_NAME"
fi

# 5. advertise the registry (KEP-1755 "local-registry-hosting")
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

kubectl get nodes -o wide
