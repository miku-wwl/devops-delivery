#!/usr/bin/env bash
# E11 I2 (chapter 12): is the remote state encrypted, and does the lock exclude a second run?
#   bash v2/experiments/e11/state-check.sh
# Talks S3 to Garage directly with curl's SigV4 (the key goes to curl through a config file of mode
# 600, not on the command line). Prints counts, never the state's content.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TOFU="bash $ROOT/v2/iac/tofu.sh gitlab"
EP="http://$(docker inspect -f '{{(index .NetworkSettings.Networks "kind-ent").IPAddress}}' backup-s3):3900/tofu-state"
STATE=gitlab/governance.tfstate
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
( umask 077; . "$HOME/.lab-secrets/v2/backup/s3-tofu.env"
  printf 'user = "%s:%s"\n' "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" > "$tmp/curl.cfg" )
s3() { curl -sS -K "$tmp/curl.cfg" --aws-sigv4 "aws:amz:garage:s3" "$@"; }
now() { date -u +%T; }

echo "== $(now) 1. the state object as Garage stores it"
code=$(s3 -o "$tmp/raw" -w '%{http_code}' "$EP/$STATE")
echo "  GET $STATE: HTTP $code, $(stat -c %s "$tmp/raw") bytes"
echo "  top-level keys: $(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$tmp/raw")"
echo "  plain-text markers in the stored object: 'platform-gitops' $(grep -c 'platform-gitops' "$tmp/raw"), 'runners_token' $(grep -c 'runners_token' "$tmp/raw"), 'only_allow_merge' $(grep -c 'only_allow_merge' "$tmp/raw")"
$TOFU state pull > "$tmp/plain" 2>/dev/null
echo "  the same markers after decryption (tofu state pull): 'platform-gitops' $(grep -c 'platform-gitops' "$tmp/plain"), 'runners_token' $(grep -c 'runners_token' "$tmp/plain"), 'only_allow_merge' $(grep -c 'only_allow_merge' "$tmp/plain")"

echo "== $(now) 2. does Garage honour If-None-Match on PUT? (what use_lockfile relies on)"
echo one > "$tmp/one"
s3 -X DELETE -o /dev/null "$EP/e11-locktest" 2>/dev/null
echo "  PUT a new object with If-None-Match: *     -> HTTP $(s3 -o /dev/null -w '%{http_code}' -H 'If-None-Match: *' -T "$tmp/one" "$EP/e11-locktest")"
echo "  PUT the same key again, If-None-Match: *   -> HTTP $(s3 -o "$tmp/resp" -w '%{http_code}' -H 'If-None-Match: *' -T "$tmp/one" "$EP/e11-locktest") $(head -c 160 "$tmp/resp" | tr -d '\n')"
s3 -X DELETE -o /dev/null "$EP/e11-locktest"

echo "== $(now) 3. another run holds the lock: a lock object placed by hand, then tofu plan"
printf '{"ID":"e11-test-0000","Operation":"OperationTypeApply","Info":"","Who":"e11-lock-test@lab","Version":"1.13.9","Created":"%s","Path":"tofu-state/%s"}' \
  "$(date -u +%FT%TZ)" "$STATE" > "$tmp/lock.json"
echo "  PUT $STATE.tflock (If-None-Match: *) -> HTTP $(s3 -o /dev/null -w '%{http_code}' -H 'If-None-Match: *' -T "$tmp/lock.json" "$EP/$STATE.tflock")"
$TOFU plan -lock-timeout=0s -no-color > "$tmp/plan" 2>&1; rc=$?
echo "  tofu plan exit code $rc:"; grep -E "Error acquiring|Lock Info|ID:|Who:|Operation:|No changes|Plan:" "$tmp/plan" | sed 's/^/    /'
echo "  lock object after the plan: HTTP $(s3 -o "$tmp/lock-after" -w '%{http_code}' "$EP/$STATE.tflock") $(grep -o '"Who":"[^"]*"' "$tmp/lock-after")"
s3 -X DELETE -o /dev/null -w '  DELETE the hand-made lock -> HTTP %{http_code}\n' "$EP/$STATE.tflock"
$TOFU plan -lock-timeout=0s -detailed-exitcode -no-color > "$tmp/plan2" 2>&1; rc=$?
echo "  tofu plan without the foreign lock: exit code $rc, $(grep -E 'No changes|Plan:|Error' "$tmp/plan2" | head -1)"
