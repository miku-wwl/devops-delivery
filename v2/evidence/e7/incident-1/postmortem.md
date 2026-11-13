# Incident E7-1: a replica silently stopped replicating after a split brain

Blameless review. Not injected: a consequence of the injected node freeze F2 that nobody predicted.

## Summary

After ent-worker2 came back from the freeze of F2, its PostgreSQL - the old primary, already
replaced by pg-main-1 - was writable for 2.5 s. In that window the replica pg-main-3 streamed WAL
from it that does not exist on the new primary's timeline. From then on pg-main-3 could not follow
the primary any more. Its pod stayed Ready, the cluster reported "Cluster in healthy state" with
3/3 ready instances, and no alert existed: for **17 minutes** (14:33-14:50) the database had one
working replica instead of two, through a planned switchover (F0d) and the experiment F3.

## Timeline (UTC, 2026-11-09)

| Time | Event | Source |
|---|---|---|
| 14:31:10 | F2: ent-worker2 frozen (`docker pause`); pg-main-2 was the primary on timeline 5 | f2-freeze/run.txt |
| 14:32:00-14:32:27 | failover: pg-main-1 promoted, timeline 6 forks off timeline 5 at 0/A22C21B0; pg-main-rw -> pg-main-1 | f2-freeze/analysis.md |
| 14:33:04.0 | ent-worker2 unpaused: the old primary resumes as a primary | run.txt |
| 14:33:05.291 | pg-main-3: "started streaming WAL from primary at 0/A2000000 on timeline 5" | state.log |
| 14:33:06.466 | old primary: "This is the former primary instance. Shutting it down" | f2-freeze/analysis.md |
| 14:33:06.731 | pg-main-3: "could not send end-of-streaming message to primary: SSL connection has been closed unexpectedly" | state.log |
| 14:33:07.952 | pg-main-3: "requested starting point 0/A3000000 on timeline 5 is not in this server's history. This server's history forked from timeline 5 at 0/A22C21B0" | state.log |
| 14:33:08.485 | pg-main-3: "new timeline 6 forked off current database system timeline 5 before current recovery point 0/A30000A0" | state.log |
| 14:33:13 | the old primary, restarted, archives its finished timeline-5 segment A2 (it extends past the fork point: a second copy of the split-brain WAL, now in the shared archive) | archive.txt |
| 14:34-14:50 | `cnpg_pg_replication_is_wal_receiver_up{pod="pg-main-3"}` = 0 | state.log |
| 14:36:31 | F0d (switchover), 14:38-14:41 F3: both with a single working replica | f0d-, f3-cut-freeze/ |
| after 14:41 | noticed while reading F3's output: "replication: pg-main-1=streaming/async" before the cut - one replica, not two | f3-cut-freeze/run.txt |
| 14:46-14:49 | alert rules added; PostgresReplicaNotStreaming (pg-main-3) and PostgresPrimaryMissingReplicas (pg-main-1) pending 14:47, firing 14:49:22 | repair.log |
| 14:49:45-14:50:10 | `kubectl cnpg destroy pg-main 3`: volume deleted, a join job clones a new pg-main-3 from the primary (25 s); 2 streaming replicas; alerts resolved | repair.log |

## Why

1. **The old primary was not fenced before it resumed.** Its instance manager stopped PostgreSQL
   2.5 s after the unpause, after it had looked at the cluster status (F2). Until then any
   connection that reached it could write - or, for a replica, stream.
2. **The replica's connection reached it.** Streaming from a timeline-5 server started 1.3 s after
   the unpause; the only timeline-5 server alive then was the old primary, while pg-main-rw had
   pointed to pg-main-1 since 14:32:27. So the connection attempt must have started while the
   service still pointed to the frozen node: a frozen node's kernel completes the TCP handshake,
   the TLS handshake then simply waits, and it completes when the node resumes. The replicas'
   `primary_conninfo` has `tcp_user_timeout='5000'` but no `connect_timeout`; against a frozen
   kernel that acknowledges every packet the TCP timeout never triggers. (The attempt's start is
   inferred; the replica's log of 14:31-14:33 was not kept before the repair.)
3. **A replica with a forked history cannot repair itself.** CloudNativePG runs pg_rewind for a
   former primary when it rejoins, not for a replica.
4. **Nothing looked at replication.** A replica's readiness does not depend on streaming; the
   cluster phase counts ready instances; the replica-side lag metric showed 0 (it compares received
   and replayed WAL, F3); the platform had no alert rule on any `cnpg_` metric.

## Changes

| Change | Where | Verified |
|---|---|---|
| Alerts: replica without WAL stream, primary with fewer than 2 streaming replicas, WAL archiving stale, base backup older than 26 h | `gitops/platform/manifests/data/pg-alerts.yaml` | both replication alerts fired on this incident 2 min after they were deployed |
| Runbook: a replica with "forked off ... before current recovery point" is re-cloned (`kubectl cnpg destroy <cluster> <n>`) | chapter 8 | repair.log |

Open: fencing that does not depend on the old primary's own reconciliation (a fenced instance does
not start PostgreSQL as primary; real infrastructure powers the old node off before promoting -
STONITH); a connect timeout for the replicas' WAL receiver, which CloudNativePG generates and does
not expose.
