#!/usr/bin/env bash
# A3 and A5 (E9, chapter 10; evidence/e9/alerting-prediction.md): warnings become GitLab tickets.
#   bash v2/experiments/e9/tickets.sh > v2/evidence/e9/a3-a5-tickets.log
# A5: a Velero backup of the namespace data with file-system backup (chapter 8: completes with warnings).
# A3: a temporary application of the project storefront writes a Secret - refused under sync
#     impersonation (chapter 9) - through the gate; removed again by a second merge request.
# Then waits until the bridge has closed both tickets (the Argo CD alert looks back 10 minutes).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GO="$ROOT/v2/gitops"
P="/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1"
now() { date -u +%T; }
state() { kubectl get --raw "$P/alerts" | python3 -c '
import json, sys
a = {x["labels"]["alertname"]: x["state"] for x in json.load(sys.stdin)["data"]["alerts"]}
print("VeleroBackupWarnings=" + a.get("VeleroBackupWarnings", "inactive"), "ArgoCDSyncFailing=" + a.get("ArgoCDSyncFailing", "inactive"))'; }
events() { docker logs --since "$T0" alert-bridge 2>&1 | grep -E '"event": "(opened|closed)"' | grep -E 'Velero|ArgoCD' | grep -o '"event": "[a-z]*", "kind": "[a-z]*", "alertname": "[A-Za-z]*", "iid": [0-9]*'; }
T0=$(date -u +%FT%TZ)
echo "== $(now) A5: Velero backup e9-warnings (namespace data, file-system backup)"
kubectl apply -f - <<'EOF' | sed 's/^/  /'
apiVersion: velero.io/v1
kind: Backup
metadata: {name: e9-warnings, namespace: velero}
spec: {includedNamespaces: [data], defaultVolumesToFsBackup: true, ttl: 24h0m0s}
EOF
echo "== $(now) A3: probe application e9-probe (a Secret in storefront) through the gate"
mkdir -p "$GO/e9-probe"
cat > "$GO/e9-probe/secret.yaml" <<'EOF'
# E9 (chapter 10), temporary: a sync that fails - the deployer account may not write Secrets.
apiVersion: v1
kind: Secret
metadata: {name: e9-probe, namespace: storefront}
stringData: {purpose: "alert test A3"}
EOF
cat > "$GO/platform/apps/e9-probe.yaml" <<'EOF'
# E9 (chapter 10), temporary: an application whose sync fails (hypothesis A3).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: e9-probe, namespace: argocd}
spec:
  project: storefront
  source: {repoURL: http://gitlab:8929/root/platform-gitops.git, targetRevision: main, path: e9-probe}
  destination: {server: "https://kubernetes.default.svc", namespace: storefront}
  syncPolicy: {automated: {prune: true, selfHeal: true}}
EOF
bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" 8ef5584 "e9: alert test A3 - a probe whose sync fails" 2>&1 | tail -1 | sed 's/^/  /'
kubectl -n argocd annotate app platform-root argocd.argoproj.io/refresh=normal --overwrite >/dev/null
for i in $(seq 1 60); do
  sleep 15
  b=$(kubectl -n velero get backups.velero.io e9-warnings -o jsonpath='{.status.phase} warnings={.status.warnings} errors={.status.errors}' 2>/dev/null)
  p=$(kubectl -n argocd get app e9-probe -o jsonpath='{.status.operationState.phase} retry={.status.operationState.retryCount}' 2>/dev/null)
  echo "  $(now) backup: $b | e9-probe: $p | $(state)"
  [ "$(events | grep -c opened)" -ge 2 ] && break
done
echo "== $(now) tickets opened:"; events | sed 's/^/  /'
echo "== $(now) A3: the probe removed through the gate"
rm -rf "$GO/e9-probe" "$GO/platform/apps/e9-probe.yaml"
bash "$ROOT/v2/platform/bootstrap/publish-gitops.sh" 8ef5584 "e9: alert test A3 done - probe removed" 2>&1 | tail -1 | sed 's/^/  /'
kubectl -n argocd annotate app platform-root argocd.argoproj.io/refresh=normal --overwrite >/dev/null
for i in $(seq 1 100); do
  sleep 15
  [ "$(events | grep -c closed)" -ge 2 ] && break
  [ $((i % 4)) = 0 ] && echo "  $(now) $(state)"
done
echo "== $(now) bridge events since $T0:"; events | sed 's/^/  /'
docker logs --since "$T0" alert-bridge 2>&1 | grep -E '"event": "(opened|closed)"' | grep -E 'Velero|ArgoCD' | cut -c1-200 | sed 's/^/  /'
