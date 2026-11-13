# E7 Velero: hypotheses (written before Velero was installed)

Velero 1.18.4 with velero-plugin-for-aws 1.14.4, backups to the bucket `velero` on the object store
outside the cluster, volume contents by the node agent's file-system backup (kopia); no volume
snapshots (the local-path provisioner has no CSI snapshot support). Every persistent volume on the
platform comes from that provisioner, and every one of them is a **hostPath** PV (`kubectl get pv`:
`spec.hostPath.path=/var/local-path-provisioner/...`).

| | Run | Hypothesis | Reasoning |
|---|---|---|---|
| V1 | `velero-drill.sh coverage v1-coverage`: backup of the namespaces data, secrets, observability, monitoring with `--default-volumes-to-fs-backup` | The backup **completes** (phase Completed, not Failed) with warnings; **none of the 11 persistent volumes is copied** - PostgreSQL x3, NATS x3, Valkey, OpenBao, Loki, Tempo, Prometheus; only emptyDir scratch volumes appear as pod volume backups. Every object of those namespaces is in it, Secrets included | Velero's file-system backup reads a volume through the kubelet's pod directory (`/var/lib/kubelet/pods/<uid>/volumes/...`); a hostPath volume is not mounted there, and Velero skips hostPath volumes as unsupported |
| V2 | `velero-drill.sh restore v2-restore`: namespace e7-velero with two PVCs - one default (hostPath PV), one annotated `volumeType: local` (the provisioner then creates a `local` PV) - a marker file in each, backed up, namespace deleted, restored | Namespace, PVCs, Deployment and ConfigMap are back in **under 1 min**; the marker on the **local** PV is restored, the one on the **hostPath** PV is not (the volume comes back empty, the app writes a new marker) | A local PV is mounted by the kubelet under the pod directory like any other volume; the hostPath one is not |

Consequence to be checked by V1/V2: for this platform Velero cannot be the backup of data, only of
Kubernetes objects; the data needs the application's own backups (PostgreSQL: Barman Cloud, E7;
OpenBao: raft snapshots), or volumes the node agent can read.
