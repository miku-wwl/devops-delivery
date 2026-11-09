# R2 (second rebuild, after the fixes of R1) against the hypotheses

Hypotheses: `rebuild-2-prediction.md` (3c52d36, before the run). T0 = 23:11:06 UTC (`destroy.txt`).

| T0 + | What | Evidence |
|---|---|---|
| 0-32 | `kind delete cluster --name ent` | destroy.txt |
| 126 | `create.sh` done; DR change committed (1c5d0a4: restore from pg-main-r1, archive as pg-main-r2) | create.txt, git |
| 197 | `bootstrap.sh` done | bootstrap.txt |
| 279 | wave -3 created (monitoring, OpenBao, Kyverno, KEDA, cert-manager, External Secrets) | wait-apps.txt |
| 305-315 | openbao-0 Running, **Ready while uninitialised** (fix 2) | openbao-ready.txt |
| 315-368 | OpenBao restored from the newest snapshot (22:26:18 - no snapshot had been taken in the 20 minutes the cluster of R1 lived: the CronJob runs at :17) | restore.txt |
| 517-556 | wave -3 done without intervention; waves -2 and -1 | wait-apps.txt |
| about 680-827 | wave 0: pg-main restored from pg-main-r1 (base backup 22:53:55 + WAL), replicas joined | wait-apps.txt |
| **903** | **all 35 applications Synced and Healthy** | wait-apps.txt |
| **919** | **first order** (23:26:25.067); k6 60 s: 514 requests, 0.00 % failed, order p95 297 ms | restore.txt |

| | Hypothesis | Measured | |
|---|---|---|---|
| R2a | no manual fix; only the planned steps | no intervention; the planned steps were the OpenBao restore, users and the load balancer limits | confirmed |
| R2b | only insight waits for OpenBao, PostgreSQL does not | not exercised: the restore (done at T0 + 368 s) finished before wave -3 did (T0 + 556 s); the fix itself showed - OpenBao Ready while uninitialised | not tested |
| R2c | first order 12-15 min after T0 | **15.3 min** (all healthy at 15.0 min); R1: 20.1 min | slightly above |
| R2d | RPO = the WAL not yet archived, 0-5 min | last archived segment D2 at 23:10:11.8; last restored write seq 12002 acknowledged 23:10:10.034; **2956 writes lost** (23:10:10.054-T0, **55.9 s**), none before; storefront: 349 orders acknowledged before T0, 287 restored, **about 62 lost** (+1 during the deletion) | confirmed |

Where the 15 minutes go now: the cluster and Argo CD 3.3 min; wave -3 alone (kube-prometheus-stack,
Kyverno, KEDA, cert-manager, External Secrets, OpenBao) 4.6 min; PostgreSQL's wave about 2.5-3 min;
the storefront 1.3 min. The waves serialise: each waits for the slowest application of the one
before. OpenBao's data lag (RPO of the secret store): 44 minutes here - the hourly snapshot had not
run on the new cluster yet; no secret had changed, so nothing was lost.
