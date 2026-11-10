#!/usr/bin/env bash
# P1 (E12, chapter 13) - practical exam: close action item 5 of incident E11-1.
#   bash v2/assessment/p1-inhibition.sh grade
# Task (README.md): while OpenBaoSealed fires, Alertmanager inhibits its symptoms - KubeJobFailed and
# KubeContainerWaiting in namespace secrets, and ArgoCDAppDegraded of the applications that depend on
# OpenBao (backup-jobs, insight, tenants, platform-root) - and nothing else. The change reaches the
# cluster through a merge request. OpenBaoSealed has no namespace label (max() drops it).
# grade:
#  1. main of root/platform-gitops: platform/values/monitoring.yaml has an inhibit rule whose source is
#     OpenBaoSealed;  2. main is protected (nobody pushes - so the change came through a merge request
#     whose pipeline succeeded);  3. the running Alertmanager has the rule;  4. behaviour: synthetic
#     alerts posted with amtool inside the Alertmanager pod, silenced first (no notification leaves
#     Alertmanager, so no incident is opened): the three symptoms are inhibited, two controls are not
#     (KubeJobFailed in storefront, ArgoCDAppDegraded of storefront-gateway); then resolved, silence expired.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
T=$(cat "$HOME/.lab-secrets/gitlab-root-token")
AMPOD=$(kubectl -n monitoring get pods -l app.kubernetes.io/name=alertmanager -o name | head -1)
am() { kubectl -n monitoring exec "$AMPOD" -c alertmanager -- amtool --alertmanager.url=http://localhost:9093 "$@"; }
git_rule() {
  curl -fsS -H "PRIVATE-TOKEN: $T" "http://localhost:8929/api/v4/projects/root%2Fplatform-gitops/repository/files/platform%2Fvalues%2Fmonitoring.yaml/raw?ref=main" |
    python3 -c 'import sys, yaml
rules = yaml.safe_load(sys.stdin)["alertmanager"]["config"].get("inhibit_rules", [])
sys.exit(0 if any("OpenBaoSealed" in " ".join(r.get("source_matchers", [])) for r in rules) else 1)'
}
main_protected() { [ "$(curl -fsS -H "PRIVATE-TOKEN: $T" "http://localhost:8929/api/v4/projects/root%2Fplatform-gitops/protected_branches/main" | jq '.push_access_levels[0].access_level')" = 0 ]; }
live_rule() { am config show | python3 -c 'import sys, yaml
rules = yaml.safe_load(sys.stdin).get("inhibit_rules", [])
sys.exit(0 if any("OpenBaoSealed" in str(r.get("source_matchers", "")) for r in rules) else 1)'; }
END=$(date -u -d '+10 minutes' +%FT%TZ)
ALERTS=(
  "src|alertname=OpenBaoSealed severity=critical team=platform"
  "t1|alertname=KubeJobFailed severity=warning namespace=secrets job_name=e12-snapshot"
  "t2|alertname=KubeContainerWaiting severity=warning namespace=secrets pod=e12-snapshot container=e12"
  "t3|alertname=ArgoCDAppDegraded severity=warning team=platform name=backup-jobs project=platform"
  "c1|alertname=KubeJobFailed severity=warning namespace=storefront job_name=e12-control"
  "c2|alertname=ArgoCDAppDegraded severity=warning team=platform name=storefront-gateway project=storefront"
)
post() {   # end time
  local a
  for a in "${ALERTS[@]}"; do am alert add ${a#*|} e12_test=true e12_id="${a%%|*}" --end="$1" >/dev/null; done
}
inhibited() {   # id -> the alert exists and something inhibits it
  am -o json alert query --active --silenced --inhibited e12_test=true e12_id="$1" | jq -e '.[0].status.inhibitedBy | length > 0'
}
not_inhibited() {   # id -> the alert exists and nothing inhibits it
  am -o json alert query --active --silenced --inhibited e12_test=true e12_id="$1" | jq -e '(.[0] != null) and (.[0].status.inhibitedBy | length == 0)'
}
case ${1:?grade} in
grade)
  echo "== $(now) P1 grade"
  check "main of platform-gitops: an inhibit rule with the source OpenBaoSealed" git_rule
  check "main is protected: changes arrive only through a merge request with a successful pipeline" main_protected
  check "the running Alertmanager has the rule" live_rule
  SIL=$(am silence add e12_test=true --duration=10m --author=e12-grader --comment="E12 P1: synthetic alerts, no notification" 2>/dev/null | tail -1)
  post "$END"; sleep 15
  check "inhibited: KubeJobFailed in secrets" inhibited t1
  check "inhibited: KubeContainerWaiting in secrets" inhibited t2
  check "inhibited: ArgoCDAppDegraded of backup-jobs" inhibited t3
  check "not inhibited: KubeJobFailed in storefront (control)" not_inhibited c1
  check "not inhibited: ArgoCDAppDegraded of storefront-gateway (control)" not_inhibited c2
  post "$(date -u +%FT%TZ)"; [ -n "$SIL" ] && am silence expire "$SIL" >/dev/null 2>&1
  verdict ;;
esac
