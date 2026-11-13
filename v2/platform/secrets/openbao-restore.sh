#!/usr/bin/env bash
# Restore OpenBao from its newest raft snapshot in the bucket platform-snapshots (E7, chapter 8).
#   bash v2/platform/secrets/openbao-restore.sh [namespace] [pod]     # default: secrets openbao-0
# For an OpenBao that has no data of its own (a rebuilt cluster, or a rehearsal next to production):
# 1. it is initialised with throwaway keys (a raft snapshot can only be restored into a running,
#    unsealed server) and unsealed with them;
# 2. the newest snapshot is streamed from the object store into the pod (a helper pod in the
#    namespace "secrets", which holds the bucket credentials, downloads it);
# 3. `bao operator raft snapshot restore -force` replaces everything, the barrier key included: the
#    server is sealed again and opens only with the ORIGINAL unseal key (~/.lab-secrets/v2/openbao/
#    init.json, kept outside the cluster) - the snapshot alone is useless, which is the point;
# 4. unsealed with that key. The original root token is valid again.
# Keys and tokens travel through stdin only. The throwaway keys are kept in init-throwaway.json.
set -euo pipefail
NS=${1:-secrets}; POD=${2:-openbao-0}
S=$HOME/.lab-secrets/v2/openbao
[ -s "$S/init.json" ] || { echo "no $S/init.json: without the original unseal key a snapshot cannot be opened"; exit 1; }
ex() { kubectl -n "$NS" exec -i "$POD" -- "$@"; }
# incident E11-1: a status only counts when OpenBao answered (bao status: 0 unsealed, 2 sealed); a
# pod's phase may still say Running from before a restart while its container does not exist
st() {
  local out rc
  out=$(ex bao status -format=json 2>/dev/null) && rc=0 || rc=$?
  { [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; } && jq -e 'has("initialized")' >/dev/null 2>&1 <<<"$out" && printf '%s' "$out"
}
s=""
for i in $(seq 1 60); do s=$(st || true); [ -n "$s" ] && break; sleep 5; done
[ -n "$s" ] || { echo "$NS/$POD does not answer after 300 s - nothing done"; exit 1; }
if [ "$(jq -r .initialized <<<"$s")" != false ]; then
  echo "$NS/$POD is initialised already - refusing to overwrite its data"; exit 1
fi
(umask 077; ex bao operator init -key-shares=1 -key-threshold=1 -format=json > "$S/init-throwaway.json")
jq -r '.unseal_keys_b64[0]' "$S/init-throwaway.json" | ex bao write -format=json sys/unseal key=- >/dev/null
for i in $(seq 1 30); do [ "$(st | jq -r .sealed)" = false ] && break; sleep 1; done
echo "initialised with throwaway keys, unsealed: $(st | jq -c '{initialized, sealed}')"

# the helper pod that reads the bucket (the job's credentials live in the namespace secrets)
IMAGE=ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie
kubectl -n secrets delete pod openbao-snapshot-fetch --ignore-not-found --wait=true >/dev/null
kubectl -n secrets run openbao-snapshot-fetch --image="$IMAGE" --restart=Never \
  --labels=app.kubernetes.io/name=openbao-snapshot-fetch \
  --overrides='{"spec":{"containers":[{"name":"f","image":"'"$IMAGE"'","command":["sleep","600"],"envFrom":[{"secretRef":{"name":"platform-snapshot-s3"}}],"securityContext":{"runAsUser":26,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' >/dev/null
kubectl -n secrets wait --for=condition=Ready pod/openbao-snapshot-fetch --timeout=120s >/dev/null
fetch() { kubectl -n secrets exec openbao-snapshot-fetch -- python3 -c "$1"; }
KEY=$(fetch 'import boto3
s3 = boto3.client("s3", endpoint_url="http://backup-s3:3900", region_name="garage")
objs = s3.list_objects_v2(Bucket="platform-snapshots", Prefix="openbao/").get("Contents", [])
print(max(objs, key=lambda o: o["LastModified"])["Key"] if objs else "")')
[ -n "$KEY" ] || { echo "no snapshot in platform-snapshots/openbao/"; exit 1; }
echo "newest snapshot: $KEY"
fetch 'import base64, sys, boto3
s3 = boto3.client("s3", endpoint_url="http://backup-s3:3900", region_name="garage")
sys.stdout.write(base64.b64encode(s3.get_object(Bucket="platform-snapshots", Key="'"$KEY"'")["Body"].read()).decode())' |
  ex sh -c 'base64 -d > /tmp/restore.snap && ls -l /tmp/restore.snap | awk "{print \"in the pod: \" \$5 \" bytes\"}"'
kubectl -n secrets delete pod openbao-snapshot-fetch --wait=false >/dev/null

# restore with the throwaway root token (first line on stdin), then open with the original key
{ jq -r .root_token "$S/init-throwaway.json"; echo 'bao operator raft snapshot restore -force /tmp/restore.snap && rm -f /tmp/restore.snap'; } |
  ex sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; sh -s'
for i in $(seq 1 30); do [ "$(st | jq -r .sealed)" = true ] && break; sleep 1; done
echo "after the restore: $(st | jq -c '{initialized, sealed}')"
jq -r '.unseal_keys_b64[0]' "$S/init.json" | ex bao write -format=json sys/unseal key=- >/dev/null
for i in $(seq 1 30); do [ "$(st | jq -r .sealed)" = false ] && break; sleep 1; done
echo "unsealed with the original key: $(st | jq -c '{initialized, sealed}')"
