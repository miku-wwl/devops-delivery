#!/usr/bin/env bash
# The drill writer (writer.py) as a pod in the namespace data (E7).
#   bash v2/experiments/e7/writer.sh start <run> <node> [rate] [deadline-s]
#   bash v2/experiments/e7/writer.sh stop <run>     # log -> evidence/e7/<run>/writer.log, pod deleted
#   bash v2/experiments/e7/writer.sh rows <run>     # seq numbers present on the current primary
#   bash v2/experiments/e7/writer.sh report <run> [t0-epoch]
# The pod is pinned to <node> (a node the drill does not touch) and uses the PostgreSQL image that is
# already on every worker (Python 3 and psycopg2 for barman-cloud).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cmd=${1:?start|stop|rows|report}; RUN=${2:?run}
POD=drill-writer-$RUN OUT="$ROOT/v2/evidence/e7/$RUN"
IMAGE=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.image}')
case $cmd in
  start)
    NODE=${3:?node}; RATE=${4:-50}; DEADLINE=${5:-2}
    kubectl -n data create configmap drill-writer --from-file=writer.py="$HERE/writer.py" \
      --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $POD, namespace: data, labels: {app: drill-writer, run: "$RUN"}}
spec:
  nodeSelector: {kubernetes.io/hostname: $NODE}
  restartPolicy: Never
  terminationGracePeriodSeconds: 2
  securityContext: {runAsNonRoot: true, runAsUser: 26, seccompProfile: {type: RuntimeDefault}}
  containers:
    - name: writer
      image: $IMAGE
      command: [python3, -u, /drill/writer.py]
      env:
        - {name: RUN, value: "$RUN"}
        - {name: RATE, value: "$RATE"}
        - {name: DEADLINE, value: "$DEADLINE"}
        - {name: PGPASSWORD, valueFrom: {secretKeyRef: {name: pg-role-drill, key: password}}}
      resources: {requests: {cpu: 20m, memory: 32Mi}, limits: {memory: 96Mi}}
      securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}, readOnlyRootFilesystem: true}
      volumeMounts: [{name: code, mountPath: /drill}]
  volumes: [{name: code, configMap: {name: drill-writer}}]
EOF
    kubectl -n data wait --for=condition=Ready "pod/$POD" --timeout=90s >/dev/null
    sleep 2; kubectl -n data logs "$POD" | sed -n 1,3p
    ;;
  stop)
    mkdir -p "$OUT"
    kubectl -n data logs "$POD" > "$OUT/writer.log"
    kubectl -n data delete pod "$POD" --wait=false >/dev/null
    echo "$(grep -c . "$OUT/writer.log") lines -> $OUT/writer.log"
    ;;
  rows)
    primary=$(kubectl -n data get cluster pg-main -o jsonpath='{.status.currentPrimary}')
    kubectl -n data exec "$primary" -c postgres -- psql -U postgres -d drill -tAc \
      "COPY (SELECT seq FROM writes WHERE run = '$RUN' ORDER BY seq) TO STDOUT"
    ;;
  report)
    mkdir -p "$OUT"
    bash "$0" rows "$RUN" > "$OUT/rows.txt"
    python3 "$HERE/writer_report.py" "$OUT/writer.log" "$OUT/rows.txt" ${3:-}
    ;;
esac
