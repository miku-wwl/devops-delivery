#!/usr/bin/env bash
# What breaks when the storefront namespace refuses plaintext? (time-boxed, reverted at the end)
#   bash v2/experiments/e2/strict.sh
# PeerAuthentication STRICT is applied by hand, outside Git, for about two minutes; Argo CD
# does not manage it, so it neither reverts nor keeps it. Three kinds of callers are tested:
#   1. east-west, mesh to mesh:   gateway pod -> orders service (HBONE, mTLS)
#   2. north-south, from outside: load balancer (envoy, outside the cluster) -> gateway
#   3. observability:             Prometheus (namespace monitoring, not in the mesh) -> /metrics
set -uo pipefail
NS=storefront
GW=$(kubectl -n $NS get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
q() { kubectl get --raw "/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query?query=$(jq -rn --arg s "$1" '$s|@uri')" |
        jq -r '.data.result[] | "\(.metric.service // .metric.job) up=\(.value[1])"' | sort | uniq -c; }
probe() {
  echo "  1. mesh -> mesh (gateway pod -> orders:8080/healthz): $(kubectl -n $NS exec deploy/gateway -c app -- python -c "
import urllib.request
try: print(urllib.request.urlopen('http://orders:8080/healthz', timeout=3).status)
except Exception as e: print(type(e).__name__, e)" 2>&1 | tail -1)"
  echo "  2. outside -> gateway (LoadBalancer $GW): $(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$GW:8080/api/products/sku-001"; echo " (curl exit $?)")"
  echo "  3. Prometheus -> storefront targets:"; q 'up{namespace="storefront"}' | sed 's/^/     /'
}
echo "== before (PERMISSIVE: plaintext and mTLS both accepted)"
probe
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: {name: strict, namespace: $NS}
spec:
  mtls: {mode: STRICT}
EOF
sleep 45   # config push to ztunnel, plus two Prometheus scrape intervals
echo "== STRICT for 45 s"
probe
kubectl -n $NS delete peerauthentication strict
sleep 45
echo "== after removing STRICT"
probe
