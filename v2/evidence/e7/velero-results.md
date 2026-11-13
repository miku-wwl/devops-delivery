# E7 Velero: results against the hypotheses

Hypotheses: `velero-prediction.md` (committed in 894fc2e, before Velero was installed). Drill:
`experiments/e7/velero-drill.sh`.

| | Hypothesis | Measured | |
|---|---|---|---|
| V1 | backup of data, secrets, observability, monitoring with file-system backup completes, with warnings; none of the 11 persistent volumes copied; only emptyDir volumes; all objects, Secrets included | **Completed**, 612/612 items, 13 warnings, 0 errors, 2 min 44 s (`v1-coverage/run.txt`). The log has one line per volume: "Volume pgdata in pod data/pg-main-1 is a hostPath volume which is not supported for pod volume backup, skipping" - all 11. Copied instead: emptyDir volumes - PostgreSQL's `scratch-data` (66-99 MB per instance), Grafana's `storage` (55 MB), `shm`, `tmp`. 22 Secrets in the backup (`v1-coverage/details.log`) | confirmed |
| V2 | after deleting the namespace, everything back in < 1 min; the file on the local PV restored, the one on the hostPath PV not | backup Completed (27 items, 1 warning; one pod volume backup: the local volume, 32 bytes); namespace deletion 51 s; restore Completed, **running 12 s** after the restore started; local PV: original marker (15:31:38); hostPath PV: a new marker written by the app after the restore (15:32:52), the volume came back empty (`v2-restore/run.txt`) | confirmed |

Two traps in what Velero reports:

- The backup with 11 unprotected volumes is **Completed**, not PartiallyFailed: the skips are
  warnings.
- The same backup log says, for those very volumes, "Skipping snapshot of pv ... because it is
  backed up with PodVolumeBackup"; the backup's own summary of skipped volumes lists them only with
  the snapshot reason ("not satisfy the criteria for VolumePolicy or the legacy snapshot way"), and
  `velero backup describe --details` simply does not list them under Backup Volumes. Only a restore
  test (V2) or reading the warnings shows that the data is not there.

Consequence for the platform: Velero stays for Kubernetes objects (daily schedule of all namespaces,
values/velero.yaml) - not as the backup of any data. The data has its own: PostgreSQL through Barman
Cloud (WAL + base backups), OpenBao through hourly raft snapshots. NATS JetStream, Valkey,
Prometheus, Loki and Tempo have none: after a total loss they start empty (rebuild drill R1). The
bucket `velero` now holds every Secret of the cluster in readable form - its key is as sensitive
as the cluster's own secrets (one key per consumer, platform/backup/object-store.sh).
