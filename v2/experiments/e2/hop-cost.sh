#!/usr/bin/env bash
# Round-trip cost of the mesh, as a 2x2 matrix (see hop_cost.py).
#   bash v2/experiments/e2/hop-cost.sh <label>
# Client pods run the storefront image on node ent-worker; the HTTP target is the catalog pod on
# ent-worker2 and the Valkey pod is on another node too, so every round trip crosses nodes.
# "in mesh" client: namespace storefront (ambient). "outside" client: namespace e2-bench.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=${1:?label}
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
CAT=$(kubectl -n storefront get pods -l app.kubernetes.io/name=catalog -o json |
      jq -r '[.items[] | select(.spec.nodeName != "ent-worker")][0].status.podIP')
VK=$(kubectl -n data get pod valkey-0 -o jsonpath='{.status.podIP}')
echo "image $IMG; http target catalog pod $CAT:8080; valkey pod $VK:6379 ($(kubectl -n data get pod valkey-0 -o jsonpath='{.spec.nodeName}'))"
kubectl create namespace e2-bench --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for ns in storefront e2-bench; do
  kubectl -n "$ns" create configmap hop-cost --from-file=hop_cost.py="$HERE/hop_cost.py" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: hop-cost, namespace: $ns}
spec:
  nodeName: ent-worker
  restartPolicy: Never
  containers:
    - name: bench
      image: $IMG
      command: ["python", "/bench/hop_cost.py", "$CAT:8080", "$VK:6379", "2000"]
      volumeMounts: [{name: bench, mountPath: /bench}]
      resources: {requests: {cpu: 100m, memory: 64Mi}, limits: {memory: 128Mi}}
  volumes: [{name: bench, configMap: {name: hop-cost}}]
EOF
  kubectl -n "$ns" wait --for=jsonpath='{.status.phase}'=Succeeded pod/hop-cost --timeout=180s >/dev/null
  echo "== client in namespace $ns ($([ "$ns" = storefront ] && echo "in the mesh" || echo "outside the mesh"))"
  kubectl -n "$ns" logs hop-cost
  kubectl -n "$ns" delete pod hop-cost --wait=false >/dev/null
done
