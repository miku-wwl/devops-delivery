# F1 (primary pod force-deleted) against the hypothesis

Hypothesis: write outage 5-15 s, 0 lost writes. Measured: **26.9 s** (14:25:57.7-14:26:24.6),
**0 lost** (3641 acknowledged, all present; 21 `fail`, 1 `unk` not committed). Outage refuted.

Where the time went (operator.log, events.txt, `kubectl logs pg-main-1 -c postgres`):

| Time | Seconds after the delete | What |
|---|---|---|
| 14:25:55.5 | 0 | `kubectl delete pod pg-main-2 --grace-period=0 --force`; kubelet stops the containers |
| 14:25:55.97 | 0.5 | operator: "Current primary isn't healthy, initiating a failover"; "Waiting for all WAL receivers to be down to elect a new primary" |
| 14:25:57.7 | 2.2 | the old PostgreSQL is gone: the writer's connection and the replicas' WAL streams break |
| 14:25:58.7 | 3.2 | target pg-main-1 (the most advanced replica) |
| 14:25:59.2 | 3.7 | pg-main-1: "Acquiring primary lease" (Lease data/pg-main, 15 s, still held by the killed primary) |
| 14:26:15.2 | 19.7 | "Acquired primary lease" - **16 s waiting for the lease to expire** |
| 14:26:15.3-20.4 | 19.8-24.9 | promotion: redo done (2 s), timeline 4 selected after reading history files from the archive (3 s), ready |
| 14:26:20.8 | 25.3 | operator: "Setting primary label" - pg-main-rw points to pg-main-1 |
| 14:26:24.6 | 29.1 | the writer's first acknowledgement (its connection attempts time out after 2 s each) |

The lease is split-brain protection: a primary that did not release it (killed, frozen, cut off)
is assumed alive until it expires, so a promotion after an unclean loss cannot be faster than the
lease duration. A planned switchover (F0b) releases it: 10.7 s.
