#!/usr/bin/env bash
# Why did a default-deny NetworkPolicy not stop traffic inside the ambient mesh (mesh-np.log)?
#   bash v2/experiments/e5/mesh-np-diag.sh
# Server pinned to ent-worker2; clients pinned to ent-worker3 (another node) and ent-worker2
# (the same node). Namespace e5-mesh (ambient) with default-deny ingress from the start, and the
# same layout in e5-plain (no mesh). A third client outside the mesh (namespace e5-plain) calls
# the meshed server. Then: how kindnet enforces policies on the node (nftables, packet marks).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
trap 'kubectl delete ns e5-plain e5-mesh --ignore-not-found --wait=false >/dev/null 2>&1' EXIT
pods() {   # ns
  kubectl -n "$1" create configmap reach-probe --from-file=reach_probe.py="$HERE/reach_probe.py" >/dev/null
  for spec in "server ent-worker2" "client-far ent-worker3" "client-near ent-worker2"; do
    set -- "$1" $spec
    kubectl -n "$1" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $2, labels: {role: $2}}
spec:
  nodeName: $3
  terminationGracePeriodSeconds: 1
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: $IMG
      command: ["python", "-m", "http.server", "8080", "--directory", "/tmp"]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
      volumeMounts: [{name: tmp, mountPath: /tmp}, {name: probe, mountPath: /probe}]
  volumes: [{name: tmp, emptyDir: {}}, {name: probe, configMap: {name: reach-probe}}]
YAML
  done
  kubectl -n "$1" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata: {name: server}
spec:
  selector: {role: server}
  ports: [{port: 8080, name: http}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny}
spec:
  podSelector: {}
  policyTypes: [Ingress]
YAML
  kubectl -n "$1" wait --for=condition=Ready pod --all --timeout=120s >/dev/null
}
try() {   # ns client target-ns
  printf "  %-26s -> server.%-9s %s\n" "$1/$2 ($(kubectl -n "$1" get pod "$2" -o jsonpath='{.spec.nodeName}'))" "$3" \
    "$(kubectl -n "$1" exec "$2" -- python /probe/reach_probe.py "s=http:server.$3.svc.cluster.local:8080" | awk '{print $2, $3}')"
}
kubectl create ns e5-plain >/dev/null; kubectl create ns e5-mesh >/dev/null
kubectl label ns e5-mesh istio.io/dataplane-mode=ambient >/dev/null
pods e5-plain; pods e5-mesh
sleep 3
echo "== default-deny ingress in both namespaces (server on ent-worker2)"
try e5-plain client-far e5-plain
try e5-plain client-near e5-plain
try e5-mesh client-far e5-mesh
try e5-mesh client-near e5-mesh
try e5-plain client-far e5-mesh
echo "== kindnet's policy enforcement on ent-worker2 (nftables)"
docker exec ent-worker2 nft list tables
docker exec ent-worker2 sh -c 'nft list ruleset | grep -n -i -E "kube-network-policies|queue|mark|15008|ztunnel|istio" | head -40'
echo "== istio-cni rules inside the meshed server pod's network namespace (inbound redirection)"
pid=$(docker exec ent-worker2 sh -c "crictl inspect \$(crictl ps --name '^c\$' --pod \$(crictl pods --namespace e5-mesh --name '^server\$' -q) -q) | jq -r .info.pid")
docker exec ent-worker2 sh -c "nsenter -t $pid -n iptables-save 2>/dev/null | head -40; nsenter -t $pid -n nft list ruleset 2>/dev/null | head -60"
