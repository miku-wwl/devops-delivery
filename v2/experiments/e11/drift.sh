#!/usr/bin/env bash
# E11 I3 (chapter 12): manual changes to the governance of root/platform-gitops - does OpenTofu see
# them, and does apply put the declared values back?   bash v2/experiments/e11/drift.sh
# [注入] the drift: three changes made as root through GitLab's API, standing in for clicks in the web
# UI: main open to Developers for push, force push allowed, alice made Maintainer.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT="$ROOT/v2/evidence/e11"
TOFU="bash $ROOT/v2/iac/tofu.sh gitlab"
T=$(cat "$HOME/.lab-secrets/gitlab-root-token")
api() { curl -fsS -H "PRIVATE-TOKEN: $T" "http://localhost:8929/api/v4/$@"; }
now() { date -u +%T; }
snap() { bash "$ROOT/v2/experiments/e11/gitlab-snapshot.sh"; }

echo "== $(now) 0. before: plan exit code $($TOFU plan -detailed-exitcode -no-color >/dev/null 2>&1; echo $?)"
echo "== $(now) 1. [注入] the drift"
api "projects/3/protected_branches/main" -X DELETE >/dev/null
api "projects/3/protected_branches" -X POST --data name=main --data push_access_level=30 \
  --data merge_access_level=40 --data allow_force_push=true >/dev/null
echo "  $(now) main re-protected with push: Developers, force push: allowed"
api "projects/3/members/5" -X PUT --data access_level=40 >/dev/null
echo "  $(now) alice: Maintainer"
snap > "$OUT/i3-gitlab-drifted.json"
echo "  GitLab now: $(jq -c '{push: .protected_main.push, force: .protected_main.allow_force_push, alice: (.members[] | select(.username == "alice") | .access_level)}' "$OUT/i3-gitlab-drifted.json")"

echo "== $(now) 2. detection: tofu plan -detailed-exitcode"
$TOFU plan -detailed-exitcode -no-color > "$OUT/i3-plan-drift.log" 2>&1; rc=$?
echo "  exit code $rc (0 = no changes, 1 = error, 2 = changes)"
grep -E '^  # |^      [~+-] |^    [~+-] |Plan:' "$OUT/i3-plan-drift.log" | sed 's/^/  /'

echo "== $(now) 3. tofu apply: back to the declared values"
$TOFU apply -auto-approve -no-color > "$OUT/i3-apply.log" 2>&1; echo "  exit code $?"
grep -E 'Modifying|Modifications complete|Destroying|Destruction complete|Creating|Creation complete|Apply complete' "$OUT/i3-apply.log" | sed 's/^/  /'

echo "== $(now) 4. after: plan exit code $($TOFU plan -detailed-exitcode -no-color >/dev/null 2>&1; echo $?)"
snap > "$OUT/i3-gitlab-restored.json"
if diff -q "$OUT/i1-gitlab-after.json" "$OUT/i3-gitlab-restored.json" >/dev/null; then
  echo "  GitLab is back to the state after the adoption (i1-gitlab-after.json = i3-gitlab-restored.json)"
else
  echo "  GitLab differs from the state after the adoption:"; diff "$OUT/i1-gitlab-after.json" "$OUT/i3-gitlab-restored.json" | sed 's/^/    /'
fi
