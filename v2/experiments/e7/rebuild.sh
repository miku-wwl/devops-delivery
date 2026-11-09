#!/usr/bin/env bash
# Rebuild drill R1 (E7, chapter 8): the cluster "ent" is lost as a whole (kind delete cluster) and
# rebuilt from what lives outside it - Git (GitHub, GitLab), the image registry and mirrors, the
# object store backup-s3, and ~/.lab-secrets. Phases, each recorded in evidence/e7/<run>/:
#   bash v2/experiments/e7/rebuild.sh before <run>     # state before; starts the drill writer
#   bash v2/experiments/e7/rebuild.sh destroy <run>    # T0: kind delete cluster --name ent
#   bash v2/experiments/e7/rebuild.sh dr-change        # pg-main.yaml: born from its predecessor's archive
#   (then platform/cluster/create.sh, platform/bootstrap/bootstrap.sh, wait-apps.sh - recorded by the caller)
#   bash v2/experiments/e7/rebuild.sh restore <run>    # OpenBao from its snapshot, users, LB limits
#   bash v2/experiments/e7/rebuild.sh verify <run>     # what came back, what did not; RPO and RTO
# The drill writer's log is streamed to the host by the caller (kubectl logs -f, it ends with the cluster).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MODE=${1:?before|destroy|dr-change|restore|verify}; RUN=${2:-r1}
OUT="$ROOT/v2/evidence/e7/$RUN"; mkdir -p "$OUT"
now() { date -u +%T; }
psqlp() { kubectl -n data exec -i "$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')" -c postgres -- psql -U postgres -tA "$@"; }
case $MODE in
before)
  exec > >(tee "$OUT/before.txt") 2>&1
  echo "== $(now) before the loss"
  kubectl get nodes --no-headers | awk '{print "  " $1, $2}'
  echo "  applications: $(kubectl -n argocd get applications --no-headers | wc -l), not Synced/Healthy: $(kubectl -n argocd get applications --no-headers | grep -vc 'Synced.*Healthy')"
  echo "  pods: $(kubectl get pods -A --no-headers | wc -l)"
  echo "  orders: $(psqlp -d orders -c "select format('%s, newest %s', count(*), max(created_at)) from orders")"
  echo "  outbox not yet published: $(psqlp -d orders -c 'select count(*) from outbox where published_at is null')"
  echo "  JetStream: $(kubectl -n data exec nats-0 -c nats -- wget -qO- http://localhost:8222/jsz | jq -c '{streams, consumers, messages}')"
  echo "  base backups: $(kubectl -n data get backups.postgresql.cnpg.io --no-headers | awk '{print $1 "=" $5}' | tr '\n' ' ')"
  echo "  OpenBao snapshots: $(kubectl -n secrets get jobs --no-headers | awk '{print $1 "=" $2}' | tr '\n' ' ')"
  echo "  secret insight/api-key sha256 prefix: $({ jq -r .root_token ~/.lab-secrets/v2/openbao/init.json; echo 'bao kv get -mount=secret -field=value insight/api-key | sha256sum | cut -c1-16'; } | kubectl -n secrets exec -i openbao-0 -- sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; sh -s')"
  bash "$HERE/writer.sh" start "$RUN" ent-worker3 50 2
  echo "  drill writer started (run $RUN)"
  ;;
destroy)
  exec > >(tee "$OUT/destroy.txt") 2>&1
  echo "== $(now) archiver right before the loss: $(psqlp -c "select last_archived_wal || ' at ' || last_archived_time || ', current ' || pg_walfile_name(pg_current_wal_lsn()) from pg_stat_archiver")"
  T0=$(date +%s); echo "$T0" > "$OUT/t0"
  echo "== $(now) T0: kind delete cluster --name ent"
  kind delete cluster --name ent
  echo "== $(now) gone after $(( $(date +%s) - T0 )) s; outside the cluster: $(docker ps --format '{{.Names}}' | grep -vE '^ent-(control-plane|worker)' | sort | tr '\n' ' ')"
  ;;
dr-change)
  # the runbook's prepared change: bootstrap from the archive of the lost cluster (serverName
  # pg-main, all WAL to the end of the archive), archive under a new name (one writer per archive)
  python3 - "$ROOT/v2/gitops/platform/manifests/data/pg-main.yaml" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = """  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters: {barmanObjectName: pg-backups}
"""
new = """  # E7 R1: this cluster was rebuilt after the loss of the whole Kubernetes cluster (chapter 8):
  # born from the archive of its predecessor (serverName pg-main: last base backup + all WAL to
  # the end of the archive) and archiving under a name of its own - an archive takes one writer.
  # The next rebuild points "source" at pg-main-r1 and archives as pg-main-r2.
  bootstrap:
    recovery:
      source: pg-main-archive
  externalClusters:
    - name: pg-main-archive
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters: {barmanObjectName: pg-backups, serverName: pg-main}
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters: {barmanObjectName: pg-backups, serverName: pg-main-r1}
"""
assert s.count(old) == 1, "pg-main.yaml does not have the expected plugins block"
p.write_text(s.replace(old, new))
print("pg-main.yaml: bootstrap from pg-main's archive, archiving as pg-main-r1")
PY
  ;;
restore)
  exec > >(tee "$OUT/restore.txt") 2>&1
  echo "== $(now) OpenBao from its newest snapshot"
  bash "$ROOT/v2/platform/secrets/openbao-restore.sh" secrets openbao-0
  bash "$ROOT/v2/platform/secrets/openbao-init.sh" 2>&1 | tail -1
  echo "== $(now) lab users (new cluster CA)"
  bash "$ROOT/v2/platform/tenants/users.sh" 2>&1 | tail -3
  bash "$ROOT/v2/platform/cluster/lb-limits.sh" >/dev/null && echo "== $(now) load balancer limits set"
  ;;
verify)
  exec > >(tee "$OUT/verify.txt") 2>&1
  T0=$(cat "$OUT/t0")
  echo "== $(now) (T0 + $(( $(date +%s) - T0 )) s) what came back"
  echo "  pg-main: $(kubectl -n data get cluster pg-main -o jsonpath='{.status.phase}, primary {.status.currentPrimary}, ready {.status.readyInstances}/{.status.instances}')"
  echo "  orders: $(psqlp -d orders -c "select format('%s, newest %s', count(*), max(created_at)) from orders")"
  echo "  outbox not yet published right after the restore: $(psqlp -d orders -c 'select count(*) from outbox where published_at is null')"
  echo "  secret insight/api-key sha256 prefix: $({ jq -r .root_token ~/.lab-secrets/v2/openbao/init.json; echo 'bao kv get -mount=secret -field=value insight/api-key | sha256sum | cut -c1-16'; } | kubectl -n secrets exec -i openbao-0 -- sh -c 'read -r BAO_TOKEN; export BAO_TOKEN; sh -s')"
  echo "  external secrets: $(kubectl get externalsecrets -A --no-headers | awk '{print $1 "/" $2 "=" $NF}' | tr '\n' ' ')"
  echo "  JetStream: $(kubectl -n data exec nats-0 -c nats -- wget -qO- http://localhost:8222/jsz | jq -c '{streams, consumers, messages}')"
  echo "  Velero sees the old backups: $(kubectl -n velero get backups.velero.io --no-headers 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
  echo "  Prometheus samples older than T0: $(kubectl get --raw "/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query?query=count(up)&time=$((T0 - 600))" | jq -r '.data.result | length')"
  echo "== RPO: the drill writer's acknowledgements against the restored rows"
  psqlp -d drill -c "copy (select seq from writes where run = '$RUN' order by seq) to stdout" > "$OUT/rows.txt"
  python3 "$HERE/writer_report.py" "$OUT/writer.log" "$OUT/rows.txt" "$T0" | sed -n '1,8p'
  last=$(sort -n "$OUT/rows.txt" | tail -1)
  echo "  last restored write: seq $last, acknowledged at $(awk -v s="$last" '$1 == "ok" && $2 == s {print $3}' "$OUT/writer.log" | xargs -I{} date -u -d @{} +%T.%3N); T0 $(date -u -d @"$T0" +%T)"
  ;;
esac
