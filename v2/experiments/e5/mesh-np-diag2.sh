#!/usr/bin/env bash
# Two hypotheses from mesh-np-diag.log, tested separately (server on ent-worker2, client on ent-worker3).
#   bash v2/experiments/e5/mesh-np-diag2.sh
# A. Connections that exist before a policy are not cut: kindnet labels a connection it has let
#    through (ct label 28) and accepts its later packets without asking again; ztunnel keeps one
#    pooled HBONE connection per pair of pods and carries every new request over it.
#      A1 no policy, one request (opens the HBONE connection); conntrack on the server's node
#      A2 default-deny ingress, a request right away
#      A3 the client pod is recreated (new IP, new HBONE connection), a request
# B. With a waypoint, the server's traffic comes from the waypoint, not from the client.
#    Policies are in place before the first request:
#      B1 default-deny + allow client -> waypoint and client -> server on 15008
#      B2 + allow waypoint -> server on 15008
# Namespaces e5-a and e5-b are deleted at the end.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
trap 'kubectl delete ns e5-a e5-b --ignore-not-found --wait=false >/dev/null 2>&1' EXIT
pod() {   # ns name node
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
}
ns() {   # name
  kubectl create ns "$1" >/dev/null
  kubectl label ns "$1" istio.io/dataplane-mode=ambient >/dev/null
  kubectl -n "$1" create configmap reach-probe --from-file=reach_probe.py="$HERE/reach_probe.py" >/dev/null
  kubectl -n "$1" apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Service
metadata: {name: server}
spec:
  selector: {role: server}
  ports: [{port: 8080, name: http}]
YAML
}
np() {   # ns name spec
  kubectl -n "$1" apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: $2}
spec:
$3
YAML
}
try() {   # ns step
  printf "  %-58s client->server: %s\n" "$2" "$(kubectl -n "$1" exec client -- python /probe/reach_probe.py "s=http:server.$1.svc.cluster.local:8080" | awk '{print $2, $3}')"
}
conn() {   # ns: connections to the server pod's port 15008, from the server node's conntrack
  local sip; sip=$(kubectl -n "$1" get pod server -o jsonpath='{.status.podIP}')
  docker exec ent-worker2 conntrack -L -p tcp --dst "$sip" --dport 15008 2>/dev/null |
    awk '{for (i = 1; i <= NF; i++) if ($i ~ /^(src|dst|sport|dport)=/ && !seen[$i]++) printf "%s ", $i; print $4}' | sed 's/^/    conntrack: /'
}
echo "== A: a connection that predates the policy (namespace e5-a)"
ns e5-a; pod e5-a server ent-worker2; pod e5-a client ent-worker3
kubectl -n e5-a wait --for=condition=Ready pod --all --timeout=120s >/dev/null
try e5-a "A1 no policy"
conn e5-a
np e5-a default-deny '  podSelector: {}
  policyTypes: [Ingress]'
sleep 5; try e5-a "A2 default-deny ingress, same client pod"
conn e5-a
kubectl -n e5-a delete pod client --wait=true >/dev/null; pod e5-a client ent-worker3
kubectl -n e5-a wait --for=condition=Ready pod/client --timeout=120s >/dev/null
try e5-a "A3 client pod recreated (new HBONE connection)"
echo "== B: with a waypoint, policies before the first request (namespace e5-b)"
ns e5-b
kubectl -n e5-b apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: waypoint, labels: {istio.io/waypoint-for: service}}
spec:
  gatewayClassName: istio-waypoint
  listeners: [{name: mesh, port: 15008, protocol: HBONE}]
YAML
kubectl label ns e5-b istio.io/use-waypoint=waypoint >/dev/null
np e5-b default-deny '  podSelector: {}
  policyTypes: [Ingress]'
np e5-b allow-client-to-waypoint '  podSelector: {matchLabels: {gateway.networking.k8s.io/gateway-name: waypoint}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {role: client}}}], ports: [{port: 15008, protocol: TCP}]}]'
np e5-b allow-client-to-server '  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {role: client}}}], ports: [{port: 15008, protocol: TCP}, {port: 8080, protocol: TCP}]}]'
pod e5-b server ent-worker2; pod e5-b client ent-worker3
kubectl -n e5-b wait --for=condition=Programmed gateway/waypoint --timeout=120s >/dev/null
kubectl -n e5-b wait --for=condition=Ready pod --all --timeout=120s >/dev/null
echo "  waypoint pod on $(kubectl -n e5-b get pods -l gateway.networking.k8s.io/gateway-name=waypoint -o jsonpath='{.items[0].spec.nodeName}')"
sleep 3
try e5-b "B1 deny + client->waypoint + client->server"
np e5-b allow-waypoint-to-server '  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {gateway.networking.k8s.io/gateway-name: waypoint}}}], ports: [{port: 15008, protocol: TCP}]}]'
sleep 5; try e5-b "B2 + waypoint->server on 15008"
conn e5-b
