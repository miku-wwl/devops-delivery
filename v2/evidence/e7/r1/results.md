# R1 (rebuild after the loss of the whole cluster) against the hypotheses

Hypotheses: `rebuild-prediction.md` (2cfd554, before the run). T0 = 22:37:23 UTC (`destroy.txt`).

## Timeline (seconds after T0)

| T0 + | What | Evidence |
|---|---|---|
| 0-54 | `kind delete cluster --name ent`: 4 nodes gone; outside: backup-s3, GitLab, registry, mirrors, ent-ccm | destroy.txt |
| 67-147 | `create.sh` (kind create 46 s, mirrors, sizes, metrics-server) | create.txt |
| 147-162 | the prepared DR change of pg-main.yaml committed (34b73e9) | git |
| 162-230 | `bootstrap.sh`: secrets from ~/.lab-secrets, image present, configuration published, Argo CD, root application | bootstrap.txt |
| 249-315 | waves -10 to -4 (projects, Gateway API, Istio) healthy | wait-apps.txt |
| 370 | **monitoring Degraded**: "pods prometheus-kps-prometheus-0 is forbidden: no PriorityClass with name platform-critical was found" - the PriorityClass is in the app policies (wave -1), Prometheus and OpenBao (wave -3) need it; the root application starts no later wave | intervention-1.log |
| 545 | **intervention 1**: the PriorityClass applied by hand from Git | intervention-1.log |
| 695 | monitoring Healthy (StatefulSet back-off, Prometheus start) | wait-apps.txt |
| 695-759 | **openbao Progressing**: a new OpenBao is uninitialised and sealed, never Ready; wave -3 never completes | intervention-2.log |
| 759-826 | **intervention 2**: the planned OpenBao restore brought forward - throwaway init, newest snapshot (22:26:18, 11 min before T0), restore, original unseal key | intervention-2.log |
| 772-873 | waves -2 and -1 (CloudNativePG, tenants, Barman Cloud plugin, NATS, Velero, ...) | wait-apps.txt |
| 873-1093 | wave 0: pg-main created 22:51:58, recovery job 22:52:07-22:53:35 (base backup of 14:15 + WAL over timelines 2-10), replicas joined | verify-2.log, wait-apps.txt |
| 1093-1171 | waves 1-2: storefront, insight; **all 34 applications Synced and Healthy** | wait-apps.txt |
| 1199-1204 | lab users re-issued (new cluster CA), load balancer limits | restore.txt |
| **1205** | **first order** (22:57:27.644) - the first one tried; k6 60 s: 509 requests, 0.00 % failed, order p95 284 ms | restore.txt |

## Against the hypotheses

| | Hypothesis | Measured | |
|---|---|---|---|
| R1a | RTO 20-30 min | **20.1 min** to the first order (all applications healthy at 19.5 min). Cluster 1.3 min and Argo CD 1.1 min instead of 3-5 each; the applications 15.7 min instead of 10-15, of which **wave -3 alone took 7.6 min** because of the two deadlocks | confirmed (lower end), composition refuted |
| R1b | RPO = the WAL not yet archived; all writes up to the end of the last archived segment restored, all later lost; window 0-5 min | last archived segment C7 at 22:34:01.9 (`destroy.txt`); last restored write seq 15521, acknowledged 22:34:00.481; **10 550 acknowledged writes lost** (22:34:00.50-T0, **202.5 s**), none before (`verify.txt`); the storefront: **147 orders acknowledged to k6 before T0** and 2 during the deletion, all lost (`k6-orders.txt`); 211 935 orders restored = the count of 22:29 | confirmed |
| R1c | OpenBao from the snapshot before T0, same secrets, original key, ExternalSecrets sync | snapshot 22:26:18; insight/api-key sha256 1251145cb0ed8b54 before and after; insight-api-key synced | confirmed |
| R1d | start empty: JetStream, Valkey, Prometheus/Loki/Tempo history, events, Argo CD history; users re-issued | JetStream 204 770 messages -> 76 (new); Prometheus: no sample older than T0; lab users new certificates | confirmed |
| R1e | at most a few outbox rows published twice | 0 unpublished rows after the restore | confirmed (0) |
| R1f | all applications converge from Git without a manual fix | **two interventions**: the PriorityClass deadlock and OpenBao's wave | refuted |

## Findings (action items)

1. **Sync waves deadlock on ordering mistakes that a running cluster never shows**: the PriorityClass
   was added (E6) to an app of a later wave than its first consumers. On the running cluster it
   existed already; only an empty cluster exposed it. Fix: cluster-wide prerequisites in an app of
   their own, before every consumer (`platform-baseline`, wave -8).
2. **A component that needs a human to become Ready blocks every later wave**: the root application
   waits for each wave to be healthy, and OpenBao (wave -3) is not Ready before someone unseals it;
   PostgreSQL (wave 0) could not even start its restore. Fix: OpenBao's readiness reports "running"
   (sealed and uninitialised count as ready); whoever needs a secret waits for the unseal, nothing
   else does.
3. The RPO of a total loss is the archive's lag: 202.5 s here, up to 5 min (`archive_timeout`) for a
   quiet database; 147 acknowledged orders were lost. A lower `archive_timeout`, or streaming WAL
   off-site (a standby cluster in another region, or `pg_receivewal`), would shrink it.
4. Velero contributed nothing to this rebuild (V1); everything came from Git, the PostgreSQL archive
   and the OpenBao snapshot. It saw its old backups at once (shared bucket).
