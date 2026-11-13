#!/usr/bin/env bash
# E11 I2 (chapter 12): the same lock test as experiments/e11/state-check.sh, against GitLab's state
# store: a foreign lock placed through GitLab's lock API, then tofu plan; then two plans at once.
#   bash v2/experiments/e11/state-lock-gitlab.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TOFU="bash $ROOT/v2/iac/tofu.sh gitlab"
T=$(cat "$HOME/.lab-secrets/gitlab-root-token")
PID=$(curl -fsS -H "PRIVATE-TOKEN: $T" "http://localhost:8929/api/v4/projects/root%2Fplatform-iac" | jq -r .id)
A="http://localhost:8929/api/v4/projects/$PID/terraform/state/gitlab"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'user = "root:%s"\n' "$T" > "$tmp/curl.cfg"; chmod 600 "$tmp/curl.cfg"
gl() { curl -sS -K "$tmp/curl.cfg" -H 'Content-Type: application/json' "$@"; }
now() { date -u +%T; }
printf '{"ID":"e11-test-0001","Operation":"OperationTypeApply","Info":"","Who":"e11-lock-test@lab","Version":"1.13.9","Created":"%s","Path":""}' \
  "$(date -u +%FT%TZ)" > "$tmp/lock.json"

echo "== $(now) 1. another run holds the lock"
echo "  POST $A/lock -> HTTP $(gl -o /dev/null -w '%{http_code}' -X POST --data @"$tmp/lock.json" "$A/lock")"
echo "  the same lock once more -> HTTP $(gl -o "$tmp/resp" -w '%{http_code}' -X POST --data @"$tmp/lock.json" "$A/lock") $(head -c 200 "$tmp/resp")"
$TOFU plan -lock-timeout=0s -no-color > "$tmp/plan" 2>&1; rc=$?
echo "  tofu plan exit code $rc:"; grep -E "Error acquiring|Error|Lock Info|ID:|Who:|Operation:|No changes|Plan:" "$tmp/plan" | sed 's/^/    /' | head -8
echo "  release: DELETE $A/lock -> HTTP $(gl -o /dev/null -w '%{http_code}' -X DELETE --data @"$tmp/lock.json" "$A/lock")"
$TOFU plan -lock-timeout=0s -detailed-exitcode -no-color > "$tmp/plan2" 2>&1; rc=$?
echo "  tofu plan without the foreign lock: exit code $rc, $(grep -E 'No changes|Plan:|Error' "$tmp/plan2" | head -1)"

echo "== $(now) 2. two plans started at the same moment (each holds the lock for its refresh and plan)"
$TOFU plan -lock-timeout=0s -detailed-exitcode -no-color > "$tmp/p1" 2>&1 & p1=$!
$TOFU plan -lock-timeout=0s -detailed-exitcode -no-color > "$tmp/p2" 2>&1 & p2=$!
wait $p1; r1=$?; wait $p2; r2=$?
for n in 1 2; do eval "r=\$r$n"; echo "  plan $n: exit code $r, $(grep -E 'Error acquiring|No changes|Plan:' "$tmp/p$n" | head -1)"; done
