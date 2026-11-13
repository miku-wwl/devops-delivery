#!/usr/bin/env bash
# Velero drills (E7, chapter 8). The velero CLI runs inside the Velero pod: its download URLs point
# to backup-s3:3900, a name only the cluster network resolves.
#   bash v2/experiments/e7/velero-drill.sh coverage <run>   # V1: file-system backup of the platform's
#                                                           # stateful namespaces - what does it contain?
#   bash v2/experiments/e7/velero-drill.sh restore <run>    # V2: namespace e7-velero with two volumes
#                                                           # (a hostPath PV and a local PV), backed up,
#                                                           # deleted, restored; are the files back?
# Resources by full name: "backup" alone is also CloudNativePG's Backup kind.
# Evidence: evidence/e7/<run>/.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MODE=${1:?coverage|restore}; RUN=${2:?run}
OUT="$ROOT/v2/evidence/e7/$RUN"; mkdir -p "$OUT"
exec > >(tee "$OUT/run.txt") 2>&1
now() { date -u +%T; }
# the server pod by name: the chart's Deployment selector also matches the node-agent pods
vel() { kubectl -n velero exec "$(kubectl -n velero get pods -o name | grep -m1 '^pod/velero-')" -c velero -- /velero "$@"; }
pvbs() { # pod volume backups of a backup: pod, volume, phase, bytes
  kubectl -n velero get podvolumebackups.velero.io -l "velero.io/backup-name=$1" -o json |
    jq -r '.items[] | "  \(.spec.pod.namespace)/\(.spec.pod.name) volume=\(.spec.volume) \(.status.phase) \(.status.progress.totalBytes // 0) bytes"'
}
NS=e7-velero
case $MODE in
coverage)
  NSS=data,secrets,observability,monitoring
  echo "== $(now) PVCs in $NSS and their PV type"
  kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef.namespace | test("^(data|secrets|observability|monitoring)$")) | "  \(.spec.claimRef.namespace)/\(.spec.claimRef.name): \(if .spec.hostPath then "hostPath" elif .spec.local then "local" else "other" end)"'
  echo "== $(now) backup $RUN (all volumes by file-system backup)"
  vel backup create "$RUN" --include-namespaces "$NSS" --default-volumes-to-fs-backup --wait 2>&1 | tail -2
  kubectl -n velero get backups.velero.io "$RUN" -o json | jq -r '"  phase \(.status.phase), items \(.status.progress.itemsBackedUp)/\(.status.progress.totalItems), warnings \(.status.warnings // 0), errors \(.status.errors // 0), \(.status.startTimestamp) - \(.status.completionTimestamp)"'
  echo "== pod volume backups (volumes whose contents were copied)"
  pvbs "$RUN"
  echo "== what the backup log says about volumes it did not copy"
  vel backup logs "$RUN" 2>/dev/null | grep -iE "hostpath|skip|not supported" | sed -E 's/.*msg="([^"]*)".*/  \1/' | sort | uniq -c | sort -rn | head -20
  vel backup describe "$RUN" --details 2>/dev/null | sed -n '/Resource List:/,/^$/p' | head -60 > "$OUT/resources.txt"
  echo "== $(grep -c '^ *- ' "$OUT/resources.txt") objects listed in resources.txt"
  ;;
restore)
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  IMAGE=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.image}')   # present on every worker
  kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-hostpath, namespace: $NS}
spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 64Mi}}}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data-local, namespace: $NS, annotations: {volumeType: local}}
spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 64Mi}}}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: app-config, namespace: $NS}
data: {greeting: "restored from a Velero backup"}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: app, namespace: $NS}
spec:
  replicas: 1
  selector: {matchLabels: {app: e7-velero}}
  template:
    metadata: {labels: {app: e7-velero}}
    spec:
      securityContext: {runAsUser: 26, fsGroup: 26}
      containers:
        - name: app
          image: $IMAGE
          command: [sh, -c, "test -f /data-hostpath/marker || echo \"\$RUN \$(date -u +%FT%TZ)\" > /data-hostpath/marker; test -f /data-local/marker || echo \"\$RUN \$(date -u +%FT%TZ)\" > /data-local/marker; exec sleep infinity"]
          env: [{name: RUN, value: "$RUN"}]
          resources: {requests: {cpu: 5m, memory: 16Mi}, limits: {memory: 64Mi}}
          volumeMounts: [{name: h, mountPath: /data-hostpath}, {name: l, mountPath: /data-local}]
      volumes:
        - {name: h, persistentVolumeClaim: {claimName: data-hostpath}}
        - {name: l, persistentVolumeClaim: {claimName: data-local}}
EOF
  kubectl -n "$NS" rollout status deploy/app --timeout=120s >/dev/null
  pod=$(kubectl -n "$NS" get pod -l app=e7-velero -o jsonpath='{.items[0].metadata.name}')
  echo "== $(now) before: PV types and the files"
  for c in data-hostpath data-local; do
    pv=$(kubectl -n "$NS" get pvc "$c" -o jsonpath='{.spec.volumeName}')
    echo "  $c -> $pv: $(kubectl get pv "$pv" -o json | jq -r 'if .spec.hostPath then "hostPath \(.spec.hostPath.path)" elif .spec.local then "local \(.spec.local.path)" else "other" end')"
    echo "    marker: $(kubectl -n "$NS" exec "$pod" -- cat "/$c/marker")"
  done
  echo "== $(now) backup $RUN"
  vel backup create "$RUN" --include-namespaces "$NS" --default-volumes-to-fs-backup --wait 2>&1 | tail -1
  kubectl -n velero get backups.velero.io "$RUN" -o json | jq -r '"  phase \(.status.phase), items \(.status.progress.itemsBackedUp), warnings \(.status.warnings // 0), errors \(.status.errors // 0)"'
  pvbs "$RUN"
  vel backup logs "$RUN" 2>/dev/null | grep -iE "hostpath|skip|not supported" | sed -E 's/.*msg="([^"]*)".*/  log: \1/' | sort -u | head -5
  echo "== $(now) the accident: kubectl delete namespace $NS"
  kubectl delete namespace "$NS" --wait=true >/dev/null
  echo "== $(now) namespace gone; restore"
  t0=$(date +%s)
  vel restore create "$RUN-restore" --from-backup "$RUN" --wait 2>&1 | tail -1
  kubectl -n velero get restores.velero.io "$RUN-restore" -o json | jq -r '"  phase \(.status.phase), items \(.status.progress.itemsRestored), warnings \(.status.warnings // 0), errors \(.status.errors // 0)"'
  kubectl -n "$NS" rollout status deploy/app --timeout=180s >/dev/null
  echo "== $(now) restored and running after $(( $(date +%s) - t0 )) s"
  pod=$(kubectl -n "$NS" get pod -l app=e7-velero -o jsonpath='{.items[0].metadata.name}')
  kubectl -n "$NS" get configmap app-config -o jsonpath='  configmap: {.data.greeting}{"\n"}'
  for c in data-hostpath data-local; do
    pv=$(kubectl -n "$NS" get pvc "$c" -o jsonpath='{.spec.volumeName}')
    echo "  $c -> $pv ($(kubectl get pv "$pv" -o json | jq -r 'if .spec.hostPath then "hostPath" elif .spec.local then "local" else "other" end')): marker $(kubectl -n "$NS" exec "$pod" -- sh -c "cat /$c/marker 2>/dev/null || echo MISSING")"
  done
  echo "  (the app writes a new marker if none exists: a marker with a later time than above is not the restored one)"
  kubectl delete namespace "$NS" --wait=false >/dev/null
  ;;
esac
