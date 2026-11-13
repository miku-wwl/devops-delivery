#!/usr/bin/env bash
# Operational cleanup after v2.0.0 (P0-P2): the lab's state, read-only. No key, token or certificate is
# printed - keys are checked by structure and compared with cmp, tokens report only their metadata
# (GitLab's /personal_access_tokens/self), tokens reach curl through a header file of mode 600.
#   bash v2/experiments/ops-1/check.sh
set -uo pipefail
S=$HOME/.lab-secrets/v2; K=$S/openbao
now() { date -u +%FT%TZ; }
echo "== $(now) lab"
echo "  context $(kubectl config current-context); nodes Ready $(kubectl get nodes --no-headers | grep -c ' Ready')/4"
echo "  applications: $(kubectl -n argocd get applications --no-headers | awk '{print $2"/"$3}' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
echo "  pods not Running/Completed: $(kubectl get pods -A --no-headers | grep -vcE 'Running|Completed')"
echo "== P0 OpenBao and its key"
echo "  status: $(kubectl -n secrets exec openbao-0 -- bao status -format=json 2>/dev/null | jq -c '{initialized, sealed, version}')"
for f in init.json init.json.copy; do
  echo "  $f: mode $(stat -c %a "$K/$f"), owner $(stat -c %U "$K/$f"), $(stat -c %s "$K/$f") bytes, key and token present: $(jq -e '(.unseal_keys_b64[0] | length > 0) and (.root_token | length > 0)' "$K/$f" >/dev/null 2>&1 && echo yes || echo NO)"
done
echo "  init.json = init.json.copy: $(cmp -s "$K/init.json" "$K/init.json.copy" && echo identical || echo DIFFERENT); directory mode $(stat -c %a "$K")"
echo "  secret sync: store insight $(kubectl -n insight get secretstore openbao -o jsonpath='{.status.conditions[0].reason}'), store shop-dev $(kubectl -n shop-dev get secretstore openbao -o jsonpath='{.status.conditions[0].reason}'), ExternalSecret insight-api-key $(kubectl -n insight get externalsecret insight-api-key -o jsonpath='{.status.conditions[0].reason}')"
I=$HOME/../../mnt/d/workshop/nov/devops-delivery/v2/platform/secrets/openbao-init.sh
[ -f "$I" ] || I=$(cd "$(dirname "$0")/../../platform/secrets" && pwd)/openbao-init.sh
echo "  openbao-init.sh guards: waits for an answer $(grep -c 'does not answer' "$I"), refuses with a key file $(grep -c 'refusing to replace a key' "$I"), atomic write $(grep -c 'init.json.new' "$I"), read-only $(grep -c 'chmod 400' "$I")"
echo "== P1 snapshot jobs"
kubectl -n secrets get cronjob openbao-snapshot -o jsonpath='  CronJob: schedule {.spec.schedule}, suspend {.spec.suspend}, last schedule {.status.lastScheduleTime}, last success {.status.lastSuccessfulTime}, failed history limit {.spec.failedJobsHistoryLimit}{"\n"}'
kubectl -n secrets get jobs -o json | jq -r '.items[] | "  job \(.metadata.name): owner \(.metadata.ownerReferences[0].kind // "none") \(.metadata.ownerReferences[0].name // ""), active \(.status.active // 0), succeeded \(.status.succeeded // 0), failed \(.status.failed // 0), started \(.status.startTime)"'
kubectl -n secrets get pods --no-headers | grep -vE 'Running|Completed' | awk '{print "  pod " $1 " " $3}'
echo "== P2 certificates and tokens"
for k in "$S"/users/*.kubeconfig; do
  echo "  $(basename "$k"): $(kubectl config view --kubeconfig "$k" --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -subject -enddate 2>/dev/null | tr '\n' ' ')"
done
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tok() {   # label, token file
  (umask 077; printf 'PRIVATE-TOKEN: %s\n' "$(tr -d '\n' < "$2")" > "$tmp/h")
  echo "  $1: $(curl -s -H @"$tmp/h" http://localhost:8929/api/v4/personal_access_tokens/self | jq -c '{name, active, revoked, expires_at, scopes, last_used_at}')"
}
tok root-admin "$HOME/.lab-secrets/gitlab-root-token"
tok alice "$S/gitlab/alice-token"
tok argocd-repo-read "$S/platform-gitops-read-token"
tok argocd-deployments "$S/gitlab/deployments-token"
(umask 077; sed -n 's/^GITLAB_TOKEN=//p' "$S/gitlab/incidents.env" > "$tmp/inc"); tok alert-bridge "$tmp/inc"
echo "== P1 memory of the workers"
for n in ent-worker ent-worker2 ent-worker3; do
  echo "  $n: $(kubectl describe node $n | sed -n '/Allocated resources/,/Events/p' | awk '/^  memory/ {print "requests " $2 " " $3 ", limits " $4 " " $5}'); usage $(kubectl top node $n --no-headers 2>/dev/null | awk '{print $4 " (" $5 ")"}')"
done
