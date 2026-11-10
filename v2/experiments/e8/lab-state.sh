#!/usr/bin/env bash
# The lab's state after a phase (E8, chapter 9; reused for later cleanup logs): what stays, what the
# drills left behind. Read-only.   bash v2/experiments/e8/lab-state.sh > v2/evidence/eN/cleanup.log
set -uo pipefail
TOKEN="$(cat "$HOME/.lab-secrets/gitlab-root-token")"
G=http://localhost:8929/api/v4/projects/root%2Fplatform-gitops
gl() { curl -fsS -H "PRIVATE-TOKEN: $TOKEN" "$G$1"; }
echo "# lab state $(date -u +%FT%TZ)"
echo "== Argo CD applications (sync/health: count)"
kubectl -n argocd get applications --no-headers | awk '{print $2 "/" $3}' | sort | uniq -c | sed 's/^/  /'
echo "== sync impersonation: $(kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.application\.sync\.impersonation\.enabled}')"
echo "== projects: accounts and sync windows"
kubectl -n argocd get appproject -o custom-columns='PROJECT:.metadata.name,ACCOUNT:.spec.destinationServiceAccounts[*].defaultServiceAccount,WINDOWS:.spec.syncWindows[*].schedule' | sed 's/^/  /'
echo "== notifications secret keys: $(kubectl -n argocd get secret argocd-notifications-secret -o jsonpath='{.data}' | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))')"
echo "== GitLab platform-gitops: freeze periods $(gl /freeze_periods | jq length), open merge requests $(gl '/merge_requests?state=opened' | jq length), deployments $(gl '/deployments?per_page=100' | jq length)"
echo "== storefront images"
kubectl -n storefront get deploy -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image' --no-headers | sed 's/^/  /'
echo "== worker memory requests (of allocatable)"
for n in $(kubectl get nodes -o name | grep worker); do
  kubectl describe "$n" | awk -v n="${n#node/}" '/^Allocated resources/ {f=1} f && $1 == "memory" {print "  " n, $2, $3; exit}'
done
echo "== pods not Running/Completed: $(kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed"' | wc -l)"
echo "== newest PostgreSQL base backup: $(kubectl -n data get backups.postgresql.cnpg.io --no-headers | tail -1 | awk '{print $1, $NF}')"
