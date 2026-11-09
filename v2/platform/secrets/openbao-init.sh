#!/usr/bin/env bash
# Initialise, unseal and configure OpenBao (E5, chapter 6). Safe to run again: it initialises only
# once, unseals only when sealed, and re-applies the configuration.
#   bash v2/platform/secrets/openbao-init.sh
# The unseal key and the root token are written to ~/.lab-secrets/v2/openbao/init.json (mode 600)
# and never printed. They reach the server through stdin, never on a command line: the API server's
# audit log records the command line of every kubectl exec (chapter 6).
# Configuration: a KV v2 store at secret/, the Kubernetes auth method (OpenBao checks a pod's
# service account token with a TokenReview), one read policy and one role per tenant. The audit device
# (stdout) is declared in the server configuration: OpenBao 2.7 refuses to enable one through the API.
set -euo pipefail
S=$HOME/.lab-secrets/v2/openbao
mkdir -p "$S"; chmod 700 "$S"
ex() { kubectl -n secrets exec -i openbao-0 -- "$@"; }
kubectl -n secrets wait --for=jsonpath='{.status.phase}'=Running pod/openbao-0 --timeout=300s >/dev/null
st() { ex bao status -format=json 2>/dev/null || true; }   # exit code 2 = sealed
if [ "$(st | jq -r .initialized)" != true ]; then
  (umask 077; ex bao operator init -key-shares=1 -key-threshold=1 -format=json > "$S/init.json")
  echo "initialised (one key share; key and root token in ~/.lab-secrets/v2/openbao/init.json)"
fi
if [ "$(st | jq -r .sealed)" = true ]; then
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
echo "configured: $(bao secrets list -format=json | grep -c '"secret/"') kv store, auth $(bao auth list -format=json | grep -o '"kubernetes/"'), policies $(bao policy list | tr '\n' ' '), audit $(bao audit list -format=json | grep -o '"stdout/"')"
CFG
} | ex sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; sh -s'
