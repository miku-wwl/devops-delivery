#!/usr/bin/env bash
# Does "kubectl exec" into a running pod stall the application in it? (observer effect)
#   bash v2/experiments/e2/exec-stall.sh
# A probe pod (outside the mesh, namespace e2-bench) calls /healthz of one payments pod every
# 20 ms for 60 s. At t = 20, 35 and 50 s a short Python process is exec'd into that payments pod,
# exactly like the connection census does. Slow probe requests are printed with their time.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG=$(kubectl -n storefront get deploy payments -o jsonpath='{.spec.template.spec.containers[0].image}')
POD=$(kubectl -n storefront get pods -l app.kubernetes.io/name=payments -o jsonpath='{.items[0].metadata.name}')
IP=$(kubectl -n storefront get pod "$POD" -o jsonpath='{.status.podIP}')
kubectl create namespace e2-bench --dry-run=client -o yaml | kubectl apply -f - >/dev/null
trap 'kubectl delete ns e2-bench --wait=false >/dev/null 2>&1' EXIT   # added in E5: the namespace was left over
kubectl -n e2-bench create configmap exec-probe --from-file=exec_probe.py="$HERE/exec_probe.py" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n e2-bench delete pod exec-probe --ignore-not-found --wait=true >/dev/null
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: exec-probe, namespace: e2-bench}
spec:
  restartPolicy: Never
  containers:
    - name: probe
      image: $IMG
      command: ["python", "/probe/exec_probe.py", "$IP:8080", "60"]
      volumeMounts: [{name: probe, mountPath: /probe}]
      resources: {requests: {cpu: 50m, memory: 32Mi}, limits: {memory: 64Mi}}
  volumes: [{name: probe, configMap: {name: exec-probe}}]
EOF
kubectl -n e2-bench wait --for=condition=Ready pod/exec-probe --timeout=60s >/dev/null
echo "probe started $(date -u +%T); target $POD ($IP)"
for t in 20 15 15; do
  sleep "$t"
  echo "exec into $POD at $(date -u +%T.%3N)"
  kubectl -n storefront exec "$POD" -c app -- python -c "print(open('/proc/net/tcp').read().count(chr(10)))" >/dev/null
  echo "        done at $(date -u +%T.%3N)"
done
kubectl -n e2-bench wait --for=jsonpath='{.status.phase}'=Succeeded pod/exec-probe --timeout=60s >/dev/null
echo "--- probe output"
kubectl -n e2-bench logs exec-probe
kubectl -n e2-bench delete pod exec-probe --wait=false >/dev/null
