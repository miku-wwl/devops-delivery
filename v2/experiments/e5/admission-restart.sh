#!/usr/bin/env bash
# One Kyverno admission controller pod is deleted; does pod admission stop, and where?
#   bash v2/experiments/e5/admission-restart.sh
# Every second for 70 s, a valid pod is created with --dry-run=server in shop-dev and insight
# (tenants: Kyverno's policies apply) and storefront (no Kyverno policy applies). A line is
# printed whenever a result changes. Used after each change to Kyverno's configuration (chapter 6).
set -uo pipefail
IMG=$(kubectl -n storefront get deploy catalog -o jsonpath='{.spec.template.spec.containers[0].image}')
pod() { printf 'apiVersion: v1\nkind: Pod\nmetadata: {name: %s}\nspec:\n  securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}\n  containers:\n    - name: c\n      image: %s\n      resources: {requests: {cpu: 10m, memory: 32Mi}, limits: {memory: 64Mi}}\n      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}\n' "$1" "$IMG"; }
echo "== Kyverno: $(kubectl -n kyverno get deploy kyverno-admission-controller -o jsonpath='{.spec.replicas}') admission controller replica(s); webhook namespaceSelector: $(kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg -o jsonpath='{.webhooks[0].namespaceSelector}')"
kubectl -n kyverno get pdb --no-headers 2>/dev/null | sed 's/^/  pdb: /'
OLD=$(kubectl -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o jsonpath='{.items[0].metadata.name}')
echo "  $(date -u +%T.%3N) deleting $OLD"
kubectl -n kyverno delete pod "$OLD" --wait=false >/dev/null
for i in $(seq 1 70); do
  line="$(date -u +%T)"
  for ns in shop-dev insight storefront; do
    if pod "p$i" | kubectl -n "$ns" create --dry-run=server -f - >/dev/null 2>/tmp/e5-err; then r=ok
    else r="FAIL($(grep -o -E 'failed calling webhook "[^"]*"|denied the request' /tmp/e5-err | head -1))"; fi
    line="$line $ns=$r"
  done
  echo "  $line"
  sleep 1
done | awk '{sig = $2 " " $3 " " $4} sig != prev {print; prev = sig} END {print "  (" NR " samples; lines are printed when a result changes)"}'
rm -f /tmp/e5-err
kubectl -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o custom-columns=POD:.metadata.name,STARTED:.status.startTime,READY:.status.conditions[1].lastTransitionTime --no-headers | sed 's/^/  /'
