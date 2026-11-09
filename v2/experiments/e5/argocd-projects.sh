#!/usr/bin/env bash
# Can an Application of project "insight" leave the team's boundary? Three attempts:
#   e5-escape-dest   the team's own manifests, but into the namespace storefront
#   e5-escape-repo   a repository the project does not list (the public Argo CD examples)
#   e5-escape-kinds  the platform's tenant manifests (namespaces, RBAC, quotas, network policies)
#                    into the namespace insight - a sync is requested explicitly
#   bash v2/experiments/e5/argocd-projects.sh
# No automated sync, no finalizer: deleting the Applications at the end touches no resource.
# Afterwards: nothing in insight or storefront changed hands (owner annotations/labels compared).
set -uo pipefail
REPO=http://gitlab:8929/root/platform-gitops.git
trap 'kubectl -n argocd delete application e5-escape-dest e5-escape-repo e5-escape-kinds --ignore-not-found >/dev/null 2>&1' EXIT
owners() { kubectl get networkpolicy,resourcequota -n insight -o json | jq -r '.items[] | "\(.kind)/\(.metadata.name) \(.metadata.annotations["argocd.argoproj.io/tracking-id"] // .metadata.labels["app.kubernetes.io/instance"] // "-")"' | sort; }
owners > /tmp/e5-own0
app() {   # name repo path namespace
  kubectl -n argocd apply -f - >/dev/null <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: $1, namespace: argocd}
spec:
  project: insight
  source: {repoURL: "$2", targetRevision: HEAD, path: $3}
  destination: {server: "https://kubernetes.default.svc", namespace: $4}
YAML
}
app e5-escape-dest "$REPO" tenants/insight storefront
app e5-escape-repo https://github.com/argoproj/argocd-example-apps.git guestbook insight
app e5-escape-kinds "$REPO" platform/manifests/tenants insight
sleep 20
for a in e5-escape-dest e5-escape-repo e5-escape-kinds; do
  echo "== $a: sync $(kubectl -n argocd get application $a -o jsonpath='{.status.sync.status}')"
  kubectl -n argocd get application $a -o json | jq -r '.status.conditions[]? | "  condition \(.type): \(.message)"' | cut -c1-300
done
echo "== e5-escape-kinds: explicit sync"
kubectl -n argocd patch application e5-escape-kinds --type merge -p '{"operation": {"initiatedBy": {"username": "e5-test"}, "sync": {"revision": "HEAD"}}}' >/dev/null
for i in $(seq 1 30); do
  ph=$(kubectl -n argocd get application e5-escape-kinds -o jsonpath='{.status.operationState.phase}')
  case "$ph" in Succeeded|Failed|Error) break;; esac; sleep 2
done
kubectl -n argocd get application e5-escape-kinds -o json | jq -r '"  operation \(.status.operationState.phase): \(.status.operationState.message)", (.status.operationState.syncResult.resources[]? | "  \(.kind)/\(.namespace // "-")/\(.name): \(.status) \(.message // "" | .[0:120])")' | cut -c1-260 | head -20
owners > /tmp/e5-own1
echo "== owners of the NetworkPolicies and the quota in insight: $(diff -q /tmp/e5-own0 /tmp/e5-own1 >/dev/null && echo unchanged || echo CHANGED)"
cat /tmp/e5-own1 | sed 's/^/  /'
rm -f /tmp/e5-own0 /tmp/e5-own1
