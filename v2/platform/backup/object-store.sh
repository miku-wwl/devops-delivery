#!/usr/bin/env bash
# The backup target of chapter 8 (E7), outside the cluster: Garage, an S3-compatible object store,
# in the Docker container backup-s3 on the cluster's network kind-ent (pods resolve the name through
# CoreDNS -> node resolver -> Docker DNS). Data in the Docker volume backup-s3-data: it survives
# `kind delete cluster`. One bucket and one access key per consumer, no key can read another
# consumer's bucket. Idempotent.
#   bash v2/platform/backup/object-store.sh
# Secrets in ~/.lab-secrets/v2/backup (mode 600, never printed, never in Git):
#   rpc_secret, admin_token, metrics_token, s3-<consumer>.env (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../versions.env"
NAME=backup-s3 NET=kind-ent VOL=backup-s3-data
SEC="$HOME/.lab-secrets/v2/backup"
# consumer -> bucket
declare -A BUCKET=([cnpg]=pg-backups [velero]=velero [platform]=platform-snapshots)
umask 077
mkdir -p "$SEC"
[ -s "$SEC/rpc_secret" ] || openssl rand -hex 32 > "$SEC/rpc_secret"
for t in admin_token metrics_token; do [ -s "$SEC/$t" ] || openssl rand -base64 32 > "$SEC/$t"; done
# the config is copied next to the secrets: a bind mount from /mnt/d would tie the container to the
# Windows checkout
install -m 600 "$HERE/garage.toml" "$SEC/garage.toml"
g() { docker exec -e RUST_LOG=warn "$NAME" /garage "$@"; }

if ! docker inspect "$NAME" >/dev/null 2>&1; then
  docker volume create "$VOL" >/dev/null
  docker run -d --name "$NAME" --restart=unless-stopped --network "$NET" --memory 256m \
    -v "$VOL:/var/lib/garage" -v "$SEC/garage.toml:/etc/garage.toml:ro" \
    -v "$SEC/rpc_secret:/run/secrets/rpc_secret:ro" -v "$SEC/admin_token:/run/secrets/admin_token:ro" \
    -v "$SEC/metrics_token:/run/secrets/metrics_token:ro" "$GARAGE_IMAGE" >/dev/null
  echo "started $NAME ($GARAGE_IMAGE)"
fi
for i in $(seq 1 30); do g status >/dev/null 2>&1 && break; sleep 1; done

# a single node holding everything (replication_factor 1)
node=$(g node id -q 2>/dev/null | cut -d@ -f1)
if g layout show 2>/dev/null | grep -q "${node:0:16}.*lab"; then
  echo "layout: node ${node:0:16} already assigned"
else
  g layout assign -z lab -c 20G "$node" >/dev/null
  cur=$(g layout show | sed -n 's/.*Current cluster layout version: \([0-9]*\).*/\1/p')
  g layout apply --version $(( ${cur:-0} + 1 )) >/dev/null
  echo "layout: node ${node:0:16} assigned (zone lab, 20 GB)"
fi

for consumer in "${!BUCKET[@]}"; do
  b=${BUCKET[$consumer]}
  g bucket info "$b" >/dev/null 2>&1 || { g bucket create "$b" >/dev/null; echo "bucket $b created"; }
  env="$SEC/s3-$consumer.env"
  if [ ! -s "$env" ]; then
    out=$(g key create "$consumer")
    id=$(sed -n 's/^Key ID: *//p' <<<"$out")
    secret=$(sed -n 's/^Secret key: *//p' <<<"$out")
    [ -n "$id" ] && [ -n "$secret" ] || { echo "could not parse the output of 'key create $consumer'" >&2; exit 1; }
    printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "$id" "$secret" > "$env"
    echo "key $consumer created ($id)"
  fi
  id=$(sed -n 's/^AWS_ACCESS_KEY_ID=//p' "$env")
  g bucket allow --read --write --owner "$b" --key "$id" >/dev/null
done

ip=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$NAME")
echo "endpoint http://$NAME:3900 ($ip), region garage"
g bucket list
