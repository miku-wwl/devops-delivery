#!/usr/bin/env bash
# After the NetworkPolicies: does everything that should work still work - with NEW connections?
#   bash v2/experiments/e5/net-validate.sh
# A policy does not cut connections that existed before it (mesh-np-diag2-2.log, part A), so a
# missing rule would show up only when a client reconnects - possibly hours later. This script
# forces the reconnects instead of waiting for them:
#   1. every storefront pod is replaced, one at a time (each Deployment keeps its replicas ready)
#   2. the clients of the data namespace that are not storefront are restarted: the KEDA operator
#      (NATS monitoring), Prometheus (exporters) and the CNPG operator (instance manager)
#   3. checks: an order flow under load (k6, 60 s), notifications sent, Prometheus targets in data,
#      storefront and keda, the ScaledObject, the PostgreSQL cluster, NATS, Argo CD, pod states
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$ROOT/v2/evidence/e5/net-validate"; mkdir -p "$OUT"
P=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1
# one number from an instant query (the first version printed "labels value" and read the second
# field; an unlabeled result has no labels, so it read nothing and reported 0 notifications)
qv() { kubectl get --raw "$P/query?query=$(jq -rn --arg q "$1" '$q|@uri')" | jq -r '.data.result[0].value[1] // "0"'; }
echo "== 1. replace every storefront pod, one at a time ($(date -u +%T))"
for d in $(kubectl -n storefront get deploy -o jsonpath='{.items[*].metadata.name}'); do
  want=$(kubectl -n storefront get deploy "$d" -o jsonpath='{.spec.replicas}')
  sel=$(kubectl -n storefront get deploy "$d" -o json | jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')
  for p in $(kubectl -n storefront get pods -l "$sel" -o jsonpath='{.items[*].metadata.name}'); do
    kubectl -n storefront delete pod "$p" --wait=true >/dev/null
    for i in $(seq 1 60); do
      [ "$(kubectl -n storefront get deploy "$d" -o jsonpath='{.status.readyReplicas}')" = "$want" ] && break; sleep 2
    done
  done
  echo "  $d: $(kubectl -n storefront get deploy "$d" -o jsonpath='{.status.readyReplicas}')/$want ready"
done
echo "== 2. restart the other clients of the data namespace ($(date -u +%T))"
kubectl -n keda delete pod -l app=keda-operator --wait=true >/dev/null
kubectl -n monitoring delete pod prometheus-kps-prometheus-0 --wait=true >/dev/null
kubectl -n cnpg-system delete pod -l app.kubernetes.io/name=cloudnative-pg --wait=true >/dev/null
kubectl -n keda wait --for=condition=Ready pod -l app=keda-operator --timeout=180s >/dev/null
kubectl -n monitoring wait --for=condition=Ready pod/prometheus-kps-prometheus-0 --timeout=300s >/dev/null
kubectl -n cnpg-system wait --for=condition=Ready pod -l app.kubernetes.io/name=cloudnative-pg --timeout=180s >/dev/null
echo "  keda-operator, prometheus, cnpg operator ready at $(date -u +%T); waiting 90 s for scrapes and polls"
sleep 90
echo "== 3a. order flow under load (k6, 20 it/s for 60 s, new connections everywhere)"
bash "$ROOT/v2/platform/cluster/lb-limits.sh" >/dev/null
GW=http://$(kubectl -n storefront get svc gateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
sent0=$(qv 'sum(notifier_messages_total{namespace="storefront",result="sent"})')
BASE_URL=$GW RATE=20 DURATION=60s SUMMARY="$OUT/k6.json" taskset -c 0-3 k6 run --quiet "$ROOT/v2/experiments/load/storefront.js" > "$OUT/k6.txt" 2>&1
python3 "$ROOT/v2/experiments/load/k6_warnings.py" "$OUT/k6.txt" >/dev/null; grep -E "requests=|browse:|order:|checks:" "$OUT/k6.txt" | sed 's/^/  /'
sleep 20
echo "  notifications sent during the run: $(qv 'sum(notifier_messages_total{namespace="storefront",result="sent"})' | awk -v a="$sent0" '{printf "%.0f", $1 - a}')"
echo "== 3b. Prometheus targets (data, storefront, keda): up / total"
kubectl get --raw "$P/targets?state=active" | jq -r '.data.activeTargets[] | select(.labels.namespace | test("^(data|storefront|keda)$")) | "\(.labels.namespace) \(.labels.job) \(.health)"' | sort | uniq -c | sed 's/^/  /'
echo "== 3c. KEDA: ScaledObject and the NATS trigger"
kubectl -n storefront get scaledobject notifier -o jsonpath='  Ready={.status.conditions[?(@.type=="Ready")].status} Active={.status.conditions[?(@.type=="Active")].status}{"\n"}'
echo "  keda-operator errors since the restart: $(kubectl -n keda logs -l app=keda-operator --since=5m | grep -c -i -E 'error|timeout|refused')"
echo "== 3d. PostgreSQL cluster (CNPG) and NATS"
kubectl -n data get cluster pg-main -o jsonpath='  pg-main: {.status.phase}, ready instances {.status.readyInstances}/{.status.instances}, primary {.status.currentPrimary}{"\n"}'
PRIM=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')
echo "  replication: $(kubectl -n data exec "$PRIM" -c postgres -- psql -qtAc "select count(*) from pg_stat_replication where state = 'streaming'" 2>/dev/null) streaming replicas seen from the primary $PRIM"
kubectl -n data get pods -l app.kubernetes.io/name=nats --no-headers | awk '{print "  " $1, $2, $3}'
echo "== 3e. Argo CD applications not Synced/Healthy: $(kubectl -n argocd get applications --no-headers -o custom-columns=A:.metadata.name,S:.status.sync.status,H:.status.health.status | grep -vcE 'Synced +Healthy')"
echo "== 3f. pods not Running/Completed: $(kubectl get pods -A --no-headers | grep -vcE 'Running|Completed')"
