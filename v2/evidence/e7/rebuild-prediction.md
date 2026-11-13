# E7 rebuild after the loss of the whole cluster: hypotheses (written before the run)

Run R1 (`experiments/e7/rebuild.sh`): `kind delete cluster --name ent` while the drill writer (50
INSERTs/s, its log streamed to the host) and k6 (5 iterations/s) are running. Rebuilt from what
lives outside the cluster: Git (GitHub; GitLab with the published configuration), the local
registry and the pull-through mirrors, the object store backup-s3 (PostgreSQL base backup from
14:15 UTC + continuous WAL; hourly OpenBao raft snapshots), `~/.lab-secrets`. Steps: the
prepared DR change of `pg-main.yaml` (bootstrap from the predecessor's archive, archive under the
new name pg-main-r1), `platform/cluster/create.sh`, `platform/bootstrap/bootstrap.sh`,
`wait-apps.sh`, `openbao-restore.sh` + `openbao-init.sh`, `users.sh`, `lb-limits.sh`.

| | Hypothesis | Reasoning |
|---|---|---|
| R1a | **RTO 20-30 min** from T0 to the first order placed against the restored data: cluster 3-5 min, Argo CD 3-5 min, the applications 10-15 min (PostgreSQL restore 2-4 min within), OpenBao and users 2 min | E0/E1 bootstrap times; restore times of the PITR drills (90-95 s) plus more WAL |
| R1b | **RPO = the WAL not yet archived**: every acknowledged write up to the end of the last archived segment is restored, every later one is lost; the window is T0 minus the last segment switch, between 0 and 5 min (`archive_timeout`) | `kind delete` kills the nodes; the current segment exists only on their disks |
| R1c | OpenBao comes back from the snapshot taken right before T0: secret hashes identical, opened with the original unseal key, the tenants' ExternalSecrets sync again | rehearsal S1 |
| R1d | Start empty: JetStream (204 770 messages now), Valkey, the history of Prometheus, Loki and Tempo, Kubernetes events, Argo CD's sync history; the lab users' certificates must be re-issued (new cluster CA) | no backup for them (Velero cannot read their hostPath volumes, V1) |
| R1e | At most a few outbox rows come back unpublished and are published a second time (at-least-once) | an event published after the end of the archive whose row was inserted before it |
| R1f | All applications converge from Git without a manual fix | everything since E1 went through GitOps - this is what the drill tests |

Safety net taken before T0, not part of the procedure: a Velero backup of all objects
(`pre-r1-objects`) and a fresh OpenBao snapshot.
