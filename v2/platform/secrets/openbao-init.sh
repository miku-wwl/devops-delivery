#!/usr/bin/env bash
# Initialise, unseal and configure OpenBao (E5, chapter 6). Safe to run again: it initialises only
# once, unseals only when sealed, and re-applies the configuration.
#   bash v2/platform/secrets/openbao-init.sh
# The unseal key and the root token are written to ~/.lab-secrets/v2/openbao/init.json (mode 600)
# and never printed. They reach the server through stdin, never on a command line: the API server's
# audit log records the command line of every kubectl exec (chapter 6).
# Configuration: a KV v2 store at secret/, the Kubernetes auth method (OpenBao checks a pod's
# service account token with a TokenReview), one read policy and one role per tenant, and (E7) the
# role of the snapshot job. The audit device
# (stdout) is declared in the server configuration: OpenBao 2.7 refuses to enable one through the API.
set -euo pipefail
S=$HOME/.lab-secrets/v2/openbao
mkdir -p "$S"; chmod 700 "$S"
ex() { kubectl -n secrets exec -i openbao-0 -- "$@"; }
# Incident E11-1 (evidence/e11/incident-1.md): the first version waited for the pod's phase - which
# still said Running from before a restart while the container did not exist yet - and treated "no
# answer" as "not initialised": it ran the initialisation with "> init.json", the shell emptied the
# only copy of the unseal key, the exec failed. Now: wait until OpenBao itself answers, never
# initialise while a key file exists, write a new key atomically and keep it read-only, twice.
st() {   # the status as JSON - only if OpenBao answered (bao status: 0 unsealed, 2 sealed)
  local out rc
  out=$(ex bao status -format=json 2>/dev/null) && rc=0 || rc=$?
  { [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; } && jq -e 'has("initialized")' >/dev/null 2>&1 <<<"$out" && printf '%s' "$out"
}
s=""
for i in $(seq 1 60); do s=$(st || true); [ -n "$s" ] && break; sleep 5; done
[ -n "$s" ] || { echo "OpenBao does not answer after 300 s - nothing done" >&2; exit 1; }
if [ "$(jq -r .initialized <<<"$s")" = false ]; then
  if [ -s "$S/init.json" ]; then
    echo "OpenBao says it is not initialised, but $S/init.json exists: refusing to replace a key." >&2
    echo "A deliberate re-initialisation (storage wiped) moves the old file away first." >&2
    exit 1
  fi
  (umask 077; ex bao operator init -key-shares=1 -key-threshold=1 -format=json > "$S/init.json.new")
  jq -e '(.unseal_keys_b64[0] | length > 0) and (.root_token | length > 0)' "$S/init.json.new" >/dev/null
  rm -f "$S/init.json"; mv "$S/init.json.new" "$S/init.json"
  rm -f "$S/init.json.copy"; cp "$S/init.json" "$S/init.json.copy"
  chmod 400 "$S/init.json" "$S/init.json.copy"   # a stray "> init.json" now fails instead of emptying it
  echo "initialised (one key share; key and root token in ~/.lab-secrets/v2/openbao/init.json, read-only, and a copy)"
  s=$(st)
fi
if [ "$(jq -r .sealed <<<"$s")" = true ]; then
  # "bao operator unseal -" takes the "-" literally; a field value "-" of "bao write" is read from stdin
  jq -r '.unseal_keys_b64[0]' "$S/init.json" | ex bao write -format=json sys/unseal key=- >/dev/null
  echo "unsealed"
fi
echo "status: $(st | jq -c '{initialized, sealed, version, storage_type}')"
# everything below runs as root inside the pod; the token is the first line on stdin
{ jq -r .root_token "$S/init.json"; cat <<'CFG'
set -e
bao secrets list -format=json | grep -q '"secret/"' || bao secrets enable -path=secret kv-v2
bao auth list -format=json | grep -q '"kubernetes/"' || bao auth enable kubernetes
bao write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc >/dev/null
printf 'path "secret/data/insight/*" { capabilities = ["read"] }\n' | bao policy write insight-read - >/dev/null
printf 'path "secret/data/shop/*" { capabilities = ["read"] }\n' | bao policy write shop-read - >/dev/null
bao write auth/kubernetes/role/insight bound_service_account_names=secrets-reader \
  bound_service_account_namespaces=insight policies=insight-read ttl=15m >/dev/null
bao write auth/kubernetes/role/shop bound_service_account_names=secrets-reader \
  bound_service_account_namespaces=shop-dev policies=shop-read ttl=15m >/dev/null
# E7: the hourly raft snapshot (gitops/platform/manifests/backup/openbao-snapshot.yaml) may read the
# snapshot endpoint and nothing else
printf 'path "sys/storage/raft/snapshot" { capabilities = ["read"] }\n' | bao policy write raft-snapshot - >/dev/null
bao write auth/kubernetes/role/raft-snapshot bound_service_account_names=openbao-snapshot \
  bound_service_account_namespaces=secrets policies=raft-snapshot ttl=5m >/dev/null
echo "configured: $(bao secrets list -format=json | grep -c '"secret/"') kv store, auth $(bao auth list -format=json | grep -o '"kubernetes/"'), policies $(bao policy list | tr '\n' ' '), audit $(bao audit list -format=json | grep -o '"stdout/"')"
CFG
} | ex sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; sh -s'
