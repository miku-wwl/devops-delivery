#!/usr/bin/env bash
# In-cluster credentials for the backup target (E7) from ~/.lab-secrets/v2/backup - the copy kept
# outside the cluster. Deliberately not from OpenBao: OpenBao itself is restored from this object
# store, and a secret store that holds the only key to its own backup cannot be rebuilt (chapter 8).
# Values travel through stdin only (no command line, no exec). Idempotent.
#   bash v2/platform/backup/secrets.sh
set -euo pipefail
SEC="$HOME/.lab-secrets/v2/backup"
kv() { sed -n "s/^$2=//p" "$SEC/s3-$1.env"; }
b64() { printf '%s' "$1" | base64 -w0; }
secret() { # namespace name key=value...
  local ns=$1 name=$2; shift 2
  { printf 'apiVersion: v1\nkind: Secret\nmetadata: {name: %s, namespace: %s, labels: {app.kubernetes.io/part-of: backup}}\ntype: Opaque\ndata:\n' "$name" "$ns"
    for kvp in "$@"; do printf '  %s: %s\n' "${kvp%%=*}" "$(b64 "${kvp#*=}")"; done
  } | kubectl apply -f - >/dev/null
  echo "secret $ns/$name"
}
for ns in data velero secrets; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done
# CloudNativePG: barmanObjectStore.s3Credentials
secret data pg-backup-s3 "ACCESS_KEY_ID=$(kv cnpg AWS_ACCESS_KEY_ID)" "ACCESS_SECRET_KEY=$(kv cnpg AWS_SECRET_ACCESS_KEY)" \
  "REGION=garage"
# Velero: an AWS shared-credentials file under the key "cloud"
secret velero velero-s3 "cloud=$(printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\n' \
  "$(kv velero AWS_ACCESS_KEY_ID)" "$(kv velero AWS_SECRET_ACCESS_KEY)")"
# OpenBao raft snapshots (platform/backup/openbao-snapshot.yaml)
secret secrets platform-snapshot-s3 "AWS_ACCESS_KEY_ID=$(kv platform AWS_ACCESS_KEY_ID)" \
  "AWS_SECRET_ACCESS_KEY=$(kv platform AWS_SECRET_ACCESS_KEY)"
