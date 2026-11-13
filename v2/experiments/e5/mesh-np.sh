#!/usr/bin/env bash
# NetworkPolicy outside and inside the ambient mesh, one rule at a time.
#   bash v2/experiments/e5/mesh-np.sh
# Two throwaway namespaces with the same server (HTTP on 8080, readiness probe every 2 s) and
# client: e5-plain (no mesh) and e5-mesh (ambient). After each step: does the client get an HTTP
# answer from the server's Service (reach_probe.py), and is the server still Ready?
#   S0 no policy
#   S1 default-deny ingress
#   S2 + allow from role=client on 8080 (the "classic" rule)
#   S3 + allow from role=client on 15008 (HBONE, the port ambient traffic arrives on)
#   S4 + allow from 169.254.7.127/32 (the address ambient gives kubelet health probes)
# e5-mesh then gets a waypoint (the storefront's setup) and the steps continue:
#   S5 use the waypoint, allow client -> waypoint on 15008
#   S6 + allow waypoint -> server on 15008
# Both namespaces (and the waypoint) are deleted at the end.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
trap 'kubectl delete ns e5-plain e5-mesh --ignore-not-found --wait=false >/dev/null 2>&1' EXIT
setup() {   # ns
  kubectl -n "$1" create configmap reach-probe --from-file=reach_probe.py="$HERE/reach_probe.py" >/dev/null
  kubectl -n "$1" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: server, labels: {role: server}}
spec:
  terminationGracePeriodSeconds: 1
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: web
      image: $IMG
      command: ["python", "-m", "http.server", "8080", "--directory", "/tmp"]
      ports: [{containerPort: 8080, name: http}]
      readinessProbe: {httpGet: {path: /, port: 8080}, periodSeconds: 2, failureThreshold: 2, timeoutSeconds: 1}
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
      volumeMounts: [{name: tmp, mountPath: /tmp}]
  volumes: [{name: tmp, emptyDir: {}}]
---
apiVersion: v1
kind: Service
metadata: {name: server}
spec:
  selector: {role: server}
  ports: [{port: 8080, targetPort: http, name: http}]
---
apiVersion: v1
kind: Pod
metadata: {name: client, labels: {role: client}}
spec:
  terminationGracePeriodSeconds: 1
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: c
      image: $IMG
      command: ["python", "-c", "import time; time.sleep(3600)"]
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
      volumeMounts: [{name: probe, mountPath: /probe}]
  volumes: [{name: probe, configMap: {name: reach-probe}}]
YAML
  kubectl -n "$1" wait --for=condition=Ready pod/server pod/client --timeout=120s >/dev/null
}
policy() {   # ns name yaml-spec
  kubectl -n "$1" apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: $2}
spec:
$3
YAML
}
check() {   # ns step
  local r ready
  r=$(kubectl -n "$1" exec client -- python /probe/reach_probe.py "server=http:server.$1.svc.cluster.local:8080" | awk '{print $2, $3}')
  ready=$(kubectl -n "$1" get pod server -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  printf "  %-9s %-62s client->server: %-14s server Ready: %s\n" "$1" "$2" "$r" "$ready"
}
kubectl create ns e5-plain >/dev/null
kubectl create ns e5-mesh >/dev/null
kubectl label ns e5-mesh istio.io/dataplane-mode=ambient >/dev/null
setup e5-plain; setup e5-mesh
for ns in e5-plain e5-mesh; do
  echo "== $ns"
  check "$ns" "S0 no policy"
  policy "$ns" default-deny '  podSelector: {}
  policyTypes: [Ingress]'
  sleep 12; check "$ns" "S1 default-deny ingress"
  policy "$ns" allow-client-8080 '  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {role: client}}}], ports: [{port: 8080, protocol: TCP}]}]'
  sleep 5; check "$ns" "S2 + allow role=client on 8080"
  policy "$ns" allow-client-hbone '  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {role: client}}}], ports: [{port: 15008, protocol: TCP}]}]'
  sleep 5; check "$ns" "S3 + allow role=client on 15008 (HBONE)"
  policy "$ns" allow-probes '  podSelector: {}
  policyTypes: [Ingress]
  ingress: [{from: [{ipBlock: {cidr: 169.254.7.127/32}}]}]'
  sleep 12; check "$ns" "S4 + allow 169.254.7.127/32 (kubelet probes in ambient)"
done
echo "== e5-mesh with a waypoint (as in storefront)"
kubectl -n e5-mesh apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: waypoint, labels: {istio.io/waypoint-for: service}}
spec:
  gatewayClassName: istio-waypoint
  listeners: [{name: mesh, port: 15008, protocol: HBONE}]
YAML
kubectl -n e5-mesh wait --for=condition=Programmed gateway/waypoint --timeout=120s >/dev/null
kubectl label ns e5-mesh istio.io/use-waypoint=waypoint >/dev/null
policy e5-mesh allow-client-to-waypoint '  podSelector: {matchLabels: {gateway.networking.k8s.io/gateway-name: waypoint}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {role: client}}}], ports: [{port: 15008, protocol: TCP}]}]'
sleep 8; check e5-mesh "S5 via waypoint; allow client -> waypoint on 15008"
policy e5-mesh allow-waypoint-to-server '  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {gateway.networking.k8s.io/gateway-name: waypoint}}}], ports: [{port: 15008, protocol: TCP}]}]'
sleep 5; check e5-mesh "S6 + allow waypoint -> server on 15008"
echo "== policies in e5-mesh at the end"
kubectl -n e5-mesh get networkpolicy --no-headers -o custom-columns=NAME:.metadata.name,POD-SELECTOR:.spec.podSelector.matchLabels
