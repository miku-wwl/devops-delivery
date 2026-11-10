#!/usr/bin/env bash
# T2 (E12, chapter 13) - "secrets stopped refreshing after a restart" (incident E11-1 as an exercise).
#   bash v2/assessment/t2-openbao-restart.sh inject|grade|restore
# inject: records the hashes of the key files, restarts openbao-0 - it comes back sealed.
# grade: OpenBao unsealed; both key files unchanged and still read-only (the failure of E11-1 was a
# recovery that destroyed the key); both SecretStores Valid and insight's ExternalSecret synced.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
K=$HOME/.lab-secrets/v2/openbao
hashes() { sha256sum "$K/init.json" "$K/init.json.copy" | awk '{print $1}'; }
unsealed() { kubectl -n secrets exec openbao-0 -- bao status -format=json 2>/dev/null | jq -e '.sealed == false'; }
keys_intact() { [ "$(hashes)" = "$(cat "$ST/t2.sha")" ] && [ ! -w "$K/init.json" ] && [ ! -w "$K/init.json.copy" ]; }
synced() {
  [ "$(kubectl -n insight get secretstore openbao -o jsonpath='{.status.conditions[0].reason}')" = Valid ] &&
  [ "$(kubectl -n shop-dev get secretstore openbao -o jsonpath='{.status.conditions[0].reason}')" = Valid ] &&
  [ "$(kubectl -n insight get externalsecret insight-api-key -o jsonpath='{.status.conditions[0].reason}')" = SecretSynced ]
}
nudge() {   # External Secrets re-checks on a change of the objects
  kubectl -n insight annotate secretstore openbao e12-recheck="$(date +%s)" --overwrite >/dev/null
  kubectl -n shop-dev annotate secretstore openbao e12-recheck="$(date +%s)" --overwrite >/dev/null
  kubectl -n insight annotate externalsecret insight-api-key force-sync="$(date +%s)" --overwrite >/dev/null
}
case ${1:?inject|grade|restore} in
inject)
  hashes > "$ST/t2.sha"
  kubectl -n secrets delete pod openbao-0 --wait=false >/dev/null
  echo "$(now) T2 injected - candidate: \"since a restart, the platform's secrets are not refreshed\"" ;;
grade)
  echo "== $(now) T2 grade"
  nudge; wait_for 120 synced
  check "OpenBao unsealed" unsealed
  check "the unseal key files unchanged and read-only (no new key, no lost key)" keys_intact
  check "both SecretStores Valid, insight's ExternalSecret synced" synced
  verdict ;;
restore)
  unsealed || bash "$ROOT/v2/platform/secrets/openbao-init.sh"
  nudge; echo "$(now) T2 restored" ;;
esac
