#!/usr/bin/env bash
# Restore rehearsal S1 (E7, chapter 8): the newest hourly OpenBao snapshot into a second, empty
# OpenBao next to production (namespace e7-bao-restore), opened with the original unseal key; one
# secret read back and compared with production by its SHA-256 (values are never printed). The
# rehearsal OpenBao is removed afterwards.
#   bash v2/experiments/e7/openbao-rehearsal.sh <run>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RUN=${1:?run}; OUT="$ROOT/v2/evidence/e7/$RUN"; mkdir -p "$OUT"
exec > >(tee "$OUT/run.txt") 2>&1
NS=e7-bao-restore REL=bao-rehearsal POD=bao-rehearsal-openbao-0
S=$HOME/.lab-secrets/v2/openbao
source "$ROOT/v2/platform/versions.env"
now() { date -u +%T; }
cleanup() { helm uninstall "$REL" -n "$NS" >/dev/null 2>&1; kubectl delete namespace "$NS" --wait=false >/dev/null 2>&1; }
trap cleanup EXIT
t0=$(date +%s)
echo "== $(now) rehearsal OpenBao ($OPENBAO_CHART_VERSION) in $NS"
helm upgrade --install "$REL" openbao --repo https://openbao.github.io/openbao-helm --version "$OPENBAO_CHART_VERSION" \
  -n "$NS" --create-namespace -f "$HERE/openbao-rehearsal-values.yaml" >/dev/null
kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Running "pod/$POD" --timeout=300s >/dev/null
echo "== $(now) restore"
bash "$ROOT/v2/platform/secrets/openbao-restore.sh" "$NS" "$POD"
# hash of one secret, read with the original root token (first line on stdin)
h() { { jq -r .root_token "$S/init.json"; echo 'bao kv get -mount=secret -field=value insight/api-key | sha256sum | cut -c1-16'; } |
      kubectl -n "$1" exec -i "$2" -- sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; sh -s'; }
echo "== $(now) secret insight/api-key, sha256 prefix: production $(h secrets openbao-0), restored $(h "$NS" "$POD")"
echo "== $(now) the throwaway root token after the restore: $({ jq -r .root_token "$S/init-throwaway.json"; echo 'bao token lookup >/dev/null 2>&1 && echo still valid || echo rejected'; } | kubectl -n "$NS" exec -i "$POD" -- sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; sh -s')"
echo "== $(now) rehearsal done in $(( $(date +%s) - t0 )) s; removing it"
