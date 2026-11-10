#!/usr/bin/env bash
# Argo CD sync impersonation (E8, chapter 9; hypotheses I1-I5 in evidence/e8/impersonation-prediction.md).
#   bash v2/experiments/e8/impersonation.sh <since, UTC ISO 8601, e.g. 2026-11-10T04:00:00Z>
# What the cluster says: the flag, the projects' accounts, what each account may do (kubectl auth can-i),
# the applications whose last sync finished since <since> and how it ended, the probe objects, and -
# from the Kubernetes audit log - who wrote them (user, impersonated user, HTTP code).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINCE=${1:?since (UTC, ISO 8601)}
echo "== $(date -u +%FT%TZ) (since $SINCE)"
echo "-- argocd-cm application.sync.impersonation.enabled: '$(kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.application\.sync\.impersonation\.enabled}')'"
echo "-- the projects' accounts (destinationServiceAccounts)"
kubectl -n argocd get appproject -o custom-columns='PROJECT:.metadata.name,NAMESPACES:.spec.destinationServiceAccounts[*].namespace,ACCOUNT:.spec.destinationServiceAccounts[*].defaultServiceAccount' | sed 's/^/  /'
echo "-- what the accounts may do (kubectl auth can-i)"
for a in argocd:argocd-application-controller argocd:argocd-platform storefront:argocd-storefront insight:argocd-insight; do
  for q in "create secrets -n storefront" "patch deployments -n storefront" "patch deployments -n insight" "get namespaces"; do
    printf '  %-40s %-30s %s\n' "$a" "$q" "$(kubectl auth can-i $q --as=system:serviceaccount:$a 2>&1)"
  done
done
echo "  argocd-application-controller impersonate serviceaccounts -n storefront: $(kubectl auth can-i impersonate serviceaccounts -n storefront --as=system:serviceaccount:argocd:argocd-application-controller 2>&1)"
echo "-- applications whose last sync finished since $SINCE (name, sync, health, phase, finished, message)"
kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\t"}{.status.operationState.phase}{"\t"}{.status.operationState.finishedAt}{"\t"}{.status.operationState.message}{"\n"}{end}' \
  | awk -F'\t' -v s="$SINCE" '$5 >= s {printf "  %s %s %s %s %s %s\n", $1, $2, $3, $4, $5, substr($6, 1, 400)}'
echo "-- all applications (sync/health: count)"
kubectl -n argocd get applications --no-headers | awk '{print $2 "/" $3}' | sort | uniq -c | sed 's/^/  /'
echo "-- the probe objects"
echo "  secret e8-probe: created $(kubectl -n storefront get secret e8-probe -o jsonpath='{.metadata.creationTimestamp}' 2>&1), written-by: '$(kubectl -n storefront get secret e8-probe -o jsonpath='{.data.written-by}' 2>/dev/null | base64 -d)'"
echo "  configmap e8-probe-ns: created $(kubectl -n storefront get configmap e8-probe-ns -o jsonpath='{.metadata.creationTimestamp}' 2>&1), write: '$(kubectl -n storefront get configmap e8-probe-ns -o jsonpath='{.data.write}' 2>/dev/null)'"
echo "-- audit log"
docker exec ent-control-plane grep -h -e e8-probe -e impersonatedUser /var/log/kubernetes/audit/audit.log \
  | python3 "$HERE/audit_who.py" "$SINCE" e8-probe e8-probe-ns | sed 's/^/  /'
