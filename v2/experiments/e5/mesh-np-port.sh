#!/usr/bin/env bash
# Which port does a NetworkPolicy have to allow for traffic inside the ambient mesh?
#   bash v2/experiments/e5/mesh-np-port.sh
# Namespace e5-c (ambient, no waypoint); server on ent-worker2. Each step uses a NEW client pod
# on ent-worker3, so every request opens a new HBONE connection (an existing one would survive a
# new policy - mesh-np-diag2-2.log, part A). Policies are in place before the client starts.
#   C1 default-deny + allow role=client on 8080 (the application's port)
#   C2 default-deny + allow role=client on 15008 (HBONE)
#   C3 the same, client outside the mesh (namespace e5-c-plain, label role=client): plain TCP to 8080
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
trap 'kubectl delete ns e5-c e5-c-plain --ignore-not-found --wait=false >/dev/null 2>&1' EXIT
pod() {   # ns name node
  kubectl -n "$1" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $2, labels: {role: ${2%%-*}}}
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
  kubectl -n "$1" wait --for=condition=Ready "pod/$2" --timeout=120s >/dev/null
}
np() {   # ns name port from-namespace(optional)
  local from='{podSelector: {matchLabels: {role: client}}}'
  [ -n "${4:-}" ] && from="{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: $4}}, podSelector: {matchLabels: {role: client}}}"
  kubectl -n "$1" apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: $2}
spec:
  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress: [{from: [$from], ports: [{port: $3, protocol: TCP}]}]
YAML
}
try() {   # client-ns client step
  printf "  %-62s client->server: %s\n" "$3" "$(kubectl -n "$1" exec "$2" -- python /probe/reach_probe.py "s=http:server.e5-c.svc.cluster.local:8080" | awk '{print $2, $3}')"
}
for ns in e5-c e5-c-plain; do
  kubectl create ns "$ns" >/dev/null
  kubectl -n "$ns" create configmap reach-probe --from-file=reach_probe.py="$HERE/reach_probe.py" >/dev/null
done
kubectl label ns e5-c istio.io/dataplane-mode=ambient >/dev/null
kubectl -n e5-c apply -f - >/dev/null <<'YAML'
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
spec: {podSelector: {}, policyTypes: [Ingress]}
YAML
pod e5-c server ent-worker2
np e5-c allow-client-app-port 8080
pod e5-c client-1 ent-worker3
try e5-c client-1 "C1 deny + allow role=client on 8080 (new client pod)"
kubectl -n e5-c delete networkpolicy allow-client-app-port >/dev/null
np e5-c allow-client-hbone 15008
pod e5-c client-2 ent-worker3
try e5-c client-2 "C2 deny + allow role=client on 15008 only (new client pod)"
np e5-c allow-plain-client-app-port 8080 e5-c-plain
pod e5-c-plain client-3 ent-worker3
try e5-c-plain client-3 "C3 client outside the mesh, allowed on 8080 from its namespace"
