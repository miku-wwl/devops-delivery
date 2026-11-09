#!/usr/bin/env bash
# Does this cluster enforce NetworkPolicy at all? (kindnet, outside the mesh)
#   bash v2/experiments/e5/np-probe.sh
# In namespace e5-np (not in the ambient mesh): a web server pod and a client pod.
#   1. no policy                 -> the client reaches the server
#   2. default-deny ingress      -> it does not (connect timeout)
#   3. allow from role=client    -> it does again
# Every step: 3 attempts, 2 s connect timeout each. The namespace is deleted at the end.
set -uo pipefail
NS=e5-np
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
trap 'kubectl delete ns $NS --wait=false >/dev/null 2>&1' EXIT
kubectl create ns $NS >/dev/null
SEC='securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}'
CSEC='securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}'
kubectl -n $NS apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: server, labels: {role: server}}
spec:
  $SEC
  containers:
    - name: web
      image: $IMG
      command: ["python", "-m", "http.server", "8080", "--directory", "/tmp"]
      volumeMounts: [{name: tmp, mountPath: /tmp}]
      $CSEC
  volumes: [{name: tmp, emptyDir: {}}]
---
apiVersion: v1
kind: Pod
metadata: {name: client, labels: {role: client}}
spec:
  $SEC
  containers:
    - name: c
      image: $IMG
      command: ["python", "-c", "import time; time.sleep(3600)"]
      $CSEC
YAML
kubectl -n $NS wait --for=condition=Ready pod/server pod/client --timeout=120s >/dev/null
SIP=$(kubectl -n $NS get pod server -o jsonpath='{.status.podIP}')
try() {   # label
  local ok=0 i
  for i in 1 2 3; do
    kubectl -n $NS exec client -- python -c "import socket; socket.create_connection(('$SIP', 8080), timeout=2).close()" >/dev/null 2>&1 && ok=$((ok + 1))
  done
  echo "  $1: $ok/3 connections to server:8080 succeeded"
}
echo "== kindnet: $(kubectl -n kube-system get ds kindnet -o jsonpath='{.spec.template.spec.containers[0].image}')"
echo "== 1. no NetworkPolicy"; try "no policy"
kubectl -n $NS apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-ingress}
spec:
  podSelector: {}
  policyTypes: [Ingress]
YAML
sleep 3
echo "== 2. default-deny ingress"; try "default deny"
kubectl -n $NS apply -f - >/dev/null <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-client}
spec:
  podSelector: {matchLabels: {role: server}}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {matchLabels: {role: client}}}]
      ports: [{port: 8080, protocol: TCP}]
YAML
sleep 3
echo "== 3. allow from role=client on 8080"; try "allowed again"
