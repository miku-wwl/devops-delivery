#!/usr/bin/env bash
# mesh-np-diag2.log, part B: with a waypoint and no "waypoint -> server" rule the request still
# succeeded. Which path did it take? Same setup as diag2 B1 (server on ent-worker2, client on
# ent-worker3, policies before the first request), plus: ztunnel's access log on the client's and
# the server's node, and every connection to port 15008 in the conntrack tables of both nodes.
#   bash v2/experiments/e5/mesh-np-diag3.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
[ "${KEEP:-0}" = 1 ] || trap 'kubectl delete ns e5-b --ignore-not-found --wait=false >/dev/null 2>&1' EXIT   # KEEP=1: leave e5-b for inspection
kubectl wait --for=delete ns/e5-b --timeout=180s >/dev/null 2>&1   # a previous run's namespace may still be terminating
kubectl create ns e5-b >/dev/null
kubectl label ns e5-b istio.io/dataplane-mode=ambient istio.io/use-waypoint=waypoint >/dev/null
kubectl -n e5-b create configmap reach-probe --from-file=reach_probe.py="$HERE/reach_probe.py" >/dev/null
kubectl -n e5-b apply -f - >/dev/null <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: waypoint, labels: {istio.io/waypoint-for: service}}
spec:
  gatewayClassName: istio-waypoint
  listeners: [{name: mesh, port: 15008, protocol: HBONE}]
---
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
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-client-to-waypoint}
spec:
  podSelector: {matchLabels: {gateway.networking.k8s.io/gateway-name: waypoint}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {role: client}}}], ports: [{port: 15008, protocol: TCP}]}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-client-to-server}
spec:
  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress: [{from: [{podSelector: {matchLabels: {role: client}}}], ports: [{port: 15008, protocol: TCP}, {port: 8080, protocol: TCP}]}]
YAML
for spec in "server ent-worker2" "client ent-worker3"; do
  set -- $spec
  kubectl -n e5-b apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $1, labels: {role: $1}}
spec:
  nodeName: $2
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
kubectl -n e5-b wait --for=condition=Programmed gateway/waypoint --timeout=120s >/dev/null
kubectl -n e5-b wait --for=condition=Ready pod --all --timeout=120s >/dev/null
sleep 3
CIP=$(kubectl -n e5-b get pod client -o jsonpath='{.status.podIP}')
SIP=$(kubectl -n e5-b get pod server -o jsonpath='{.status.podIP}')
WIP=$(kubectl -n e5-b get pods -l gateway.networking.k8s.io/gateway-name=waypoint -o jsonpath='{.items[0].status.podIP}')
WN=$(kubectl -n e5-b get pods -l gateway.networking.k8s.io/gateway-name=waypoint -o jsonpath='{.items[0].spec.nodeName}')
echo "== client $CIP (ent-worker3), server $SIP (ent-worker2), waypoint $WIP ($WN)"
T=$(date -u +%FT%TZ)
echo "  request: $(kubectl -n e5-b exec client -- python /probe/reach_probe.py "s=http:server.e5-b.svc.cluster.local:8080")"
sleep 2
for node in ent-worker3 ent-worker2 "$WN"; do
  zt=$(kubectl -n istio-system get pods -l app=ztunnel --field-selector spec.nodeName="$node" -o jsonpath='{.items[0].metadata.name}')
  echo "== ztunnel on $node ($zt): access log lines for e5-b since $T"
  kubectl -n istio-system logs "$zt" --since-time="$T" | grep -E "e5-b" | grep -E "access|connection" | tail -4 | cut -c1-420
done
for node in ent-worker2 "$WN"; do
  echo "== conntrack on $node: connections to port 15008 involving the client, server or waypoint"
  docker exec "$node" conntrack -L -p tcp --dport 15008 2>/dev/null | grep -E "$CIP|$SIP|$WIP" |
    awk '{printf "  "; for (i = 1; i <= NF; i++) if ($i ~ /^(src|dst|dport)=/ && !seen[NR, $i]++) printf "%s ", $i; print $4}'
done
