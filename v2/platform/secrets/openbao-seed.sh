#!/usr/bin/env bash
# The two test values of E5 (chapter 6), written into OpenBao when they are missing - after a
# re-initialisation (incident E11-1). Random values; they and the root token reach OpenBao through
# stdin, never on a command line; only short hashes are printed. Idempotent.
#   bash v2/platform/secrets/openbao-seed.sh
set -euo pipefail
S=$HOME/.lab-secrets/v2/openbao
ex() { kubectl -n secrets exec -i openbao-0 -- "$@"; }
for path in insight/api-key shop/db-password; do
  if jq -r .root_token "$S/init.json" |
     ex sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; bao kv get -mount=secret "$0" >/dev/null 2>&1' "$path" 2>/dev/null; then
    echo "secret/$path exists - left as it is"; continue
  fi
  v=$(openssl rand -hex 16)
  { jq -r .root_token "$S/init.json"; printf '%s\n' "$v"; } |
    ex sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; read -r V; bao kv put -mount=secret "$0" value="$V" >/dev/null' "$path"
  echo "secret/$path written ($(printf %s "$v" | sha256sum | cut -c1-12)...)"
done
