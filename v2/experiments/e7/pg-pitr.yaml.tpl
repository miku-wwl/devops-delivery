# A temporary recovery cluster (E7 point-in-time recovery, chapter 8): one instance, restored from
# the archive of pg-main (last base backup before the target + all WAL up to the target), next to
# the production cluster. Never archives (no WAL archiver plugin): it must not write into the
# archive it reads from. Rendered by pitr.sh (TARGET_TIME, IMAGE); applied with kubectl, deleted
# after the rows have been copied back.
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-pitr
  namespace: data
  labels: {app.kubernetes.io/part-of: e7-drill}
spec:
  instances: 1
  imageName: ${IMAGE}
  storage: {size: 2Gi}
  resources:
    requests: {cpu: 50m, memory: 256Mi}
    limits: {memory: 512Mi}
  postgresql:
    parameters: {shared_buffers: 64MB, max_connections: "50"}
  bootstrap:
    recovery:
      source: pg-main-archive
      recoveryTarget:
        targetTime: "${TARGET_TIME}"
  externalClusters:
    - name: pg-main-archive
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters: {barmanObjectName: pg-backups, serverName: pg-main}
