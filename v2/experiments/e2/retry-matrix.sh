#!/usr/bin/env bash
# Retry layering, four scenarios with payments failing every charge ([注入]):
#   S1 waypoint (L7), payments answers 500
#   S2 waypoint (L7), payments answers 503    - does the default route policy retry 503? (no)
#   S3 waypoint (L7), 503, plus an HTTPRoute with retry: attempts 3 on 503
#   S4 ztunnel only (L4, no waypoint), 503    - L4 cannot retry HTTP
# The HTTPRoute and the namespace label are changed by hand for the experiment (Argo CD
# automated sync is paused meanwhile) and restored at the end, also on Ctrl-C.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pause() { for a in platform-root namespaces; do
            kubectl -n argocd patch application "$a" --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null; done; }
resume() { kubectl -n storefront delete httproute payments-retry --ignore-not-found >/dev/null
           kubectl label ns storefront istio.io/use-waypoint=waypoint --overwrite >/dev/null
           kubectl -n argocd patch application namespaces --type merge \
             -p '{"spec":{"syncPolicy":{"automated":{"prune":false,"selfHeal":true}}}}' >/dev/null
           kubectl -n argocd patch application platform-root --type merge \
             -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
           echo "restored: no HTTPRoute, namespace uses the waypoint, Argo CD automated sync on"; }
trap resume EXIT
pause
kubectl label ns storefront istio.io/use-waypoint=waypoint --overwrite >/dev/null; sleep 10
bash "$HERE/retry-layers.sh" S1-L7-500 500
bash "$HERE/retry-layers.sh" S2-L7-503 503
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: payments-retry, namespace: storefront}
spec:
  parentRefs:
    - {group: "", kind: Service, name: payments, port: 8080}
  rules:
    - backendRefs: [{name: payments, port: 8080}]
      retry:
        codes: [503]
        attempts: 3
        backoff: 25ms
EOF
sleep 10
kubectl -n storefront get httproute payments-retry -o jsonpath='{.status.parents[0].conditions[*].type}={.status.parents[0].conditions[*].status}{"\n"}'
bash "$HERE/retry-layers.sh" S3-L7-503-route-retry3 503
kubectl -n storefront delete httproute payments-retry >/dev/null; sleep 5
kubectl label ns storefront istio.io/use-waypoint- >/dev/null; sleep 15
bash "$HERE/retry-layers.sh" S4-L4-503 503
