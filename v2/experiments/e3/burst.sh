#!/usr/bin/env bash
# Many new connections at once - through the node's ztunnel, and without it.
#   bash v2/experiments/e3/burst.sh <label> [node] [n ...]
# Two identical probe pods on the same node: one in the storefront namespace (ambient mesh, so
# its traffic is redirected to the node's ztunnel), one in the data namespace (not in the mesh).
# Both open n connections to valkey-0 at once (burst_connect.py), in the order mesh, no mesh,
# mesh (A-B-A, to see drift). No load on the system otherwise; the pods are deleted at the end.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=${1:?label}; NODE=${2:-ent-worker}; shift 2 || true
SIZES=${*:-1 10 50 100 200}
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
VALKEY=$(kubectl -n data get pod valkey-0 -o jsonpath='{.status.podIP}')
VNODE=$(kubectl -n data get pod valkey-0 -o jsonpath='{.spec.nodeName}')
for ns in storefront data; do
  kubectl -n "$ns" apply -f - > /dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: e3-burst, labels: {app: e3-burst}}
spec:
  nodeName: $NODE
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: probe
      image: $IMG
      command: ["sleep", "900"]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
      resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 128Mi}}
YAML
done
trap 'kubectl -n storefront delete pod e3-burst --wait=false >/dev/null; kubectl -n data delete pod e3-burst --wait=false >/dev/null' EXIT
kubectl -n storefront wait --for=condition=Ready pod/e3-burst --timeout=120s > /dev/null
kubectl -n data wait --for=condition=Ready pod/e3-burst --timeout=120s > /dev/null
echo "target valkey-0 $VALKEY:6379 on $VNODE; both probe pods on $NODE; image $IMG"
for ns in storefront data; do
  echo "probe in $ns: redirection annotation = $(kubectl -n "$ns" get pod e3-burst \
    -o jsonpath='{.metadata.annotations.ambient\.istio\.io/redirection}')"
done
for ns in storefront data storefront; do
  if [ "$ns" = storefront ]; then echo "=== in the mesh (through ztunnel on $NODE)"; else echo "=== outside the mesh"; fi
  kubectl -n "$ns" exec -i e3-burst -- python - "$VALKEY" 6379 $SIZES < "$HERE/burst_connect.py"
done
