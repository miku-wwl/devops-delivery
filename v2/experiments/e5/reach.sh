#!/usr/bin/env bash
# Who can reach whom: a probe pod in each source namespace tries every target with an
# application-level request (reach_probe.py) and the results are printed as a matrix.
#   bash v2/experiments/e5/reach.sh <label> [expected.tsv]
# Sources: insight and shop-dev (tenants), storefront (in the ambient mesh, behind the waypoint
# for its own services), e5-outside (a namespace without any policy: "any other workload") and
# monitoring (where Prometheus runs: what the scrapers may reach).
# With an expectations file (source<TAB>target<TAB>ok|blocked), every cell is compared and the
# script exits 1 on a mismatch. Probe pods, their ConfigMaps and e5-outside are deleted at the end.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
LABEL=${1:?label}; EXP=${2:-}
OUT="$ROOT/v2/evidence/e5/$LABEL"; mkdir -p "$OUT"
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
SOURCES=(insight shop-dev storefront e5-outside monitoring)
TARGETS=(
  "dns=dns:kubernetes.default.svc.cluster.local:0"
  "catalog=http:catalog.storefront.svc.cluster.local:8080"
  "gateway=http:gateway.storefront.svc.cluster.local:8080"
  "postgres=pg:pg-main-rw.data.svc.cluster.local:5432"
  "valkey=redis:valkey.data.svc.cluster.local:6379"
  "nats=nats:nats.data.svc.cluster.local:4222"
  "insight-api=http:insight-api.insight.svc.cluster.local:8080"
  "prometheus=http:kps-prometheus.monitoring.svc.cluster.local:9090"
  "otel=http:otel-collector.observability.svc.cluster.local:4318"
)
cleanup() {
  for ns in insight shop-dev storefront monitoring; do
    kubectl -n "$ns" delete pod reach-probe --ignore-not-found --wait=false >/dev/null 2>&1
    kubectl -n "$ns" delete configmap reach-probe --ignore-not-found >/dev/null 2>&1
  done
  kubectl delete ns e5-outside --ignore-not-found --wait=false >/dev/null 2>&1
}
trap cleanup EXIT
kubectl wait --for=delete ns/e5-outside --timeout=180s >/dev/null 2>&1   # a previous run may still be deleting it
kubectl create ns e5-outside --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for ns in "${SOURCES[@]}"; do
  kubectl -n "$ns" create configmap reach-probe --from-file=reach_probe.py="$HERE/reach_probe.py" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ns" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: reach-probe, labels: {app: reach-probe}}
spec:
  terminationGracePeriodSeconds: 1
  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: probe
      image: $IMG
      command: ["python", "-c", "import time; time.sleep(3600)"]
      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
      volumeMounts: [{name: probe, mountPath: /probe}]
  volumes: [{name: probe, configMap: {name: reach-probe}}]
YAML
done
for ns in "${SOURCES[@]}"; do kubectl -n "$ns" wait --for=condition=Ready pod/reach-probe --timeout=120s >/dev/null; done
for ns in "${SOURCES[@]}"; do
  kubectl -n "$ns" exec reach-probe -- python /probe/reach_probe.py "${TARGETS[@]}" > "$OUT/$ns.txt" 2>&1 &
done
wait
names=(); for t in "${TARGETS[@]}"; do names+=("${t%%=*}"); done
{ printf "source"; printf "\t%s" "${names[@]}"; echo
  for ns in "${SOURCES[@]}"; do
    printf "%s" "$ns"
    for n in "${names[@]}"; do printf "\t%s" "$(awk -v n="$n" '$1 == n {print $2}' "$OUT/$ns.txt")"; done; echo
  done; } > "$OUT/matrix.tsv"
column -t -s $'\t' "$OUT/matrix.tsv"
if [ -n "$EXP" ]; then
  bad=0; n=0
  while IFS=$'\t' read -r src tgt want; do
    case "$src" in ''|'#'*) continue;; esac
    got=$(awk -v n="$tgt" '$1 == n {print $2}' "$OUT/$src.txt"); have=blocked; [ "$got" = ok ] && have=ok
    n=$((n + 1)); [ "$have" = "$want" ] || { bad=$((bad + 1)); echo "  MISMATCH $src -> $tgt: expected $want, got $got"; }
  done < "$EXP"
  echo "== $n cells compared with $(basename "$EXP"): $((n - bad)) as expected, $bad mismatches"
  [ "$bad" -eq 0 ]
fi
