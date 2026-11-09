# E7 PostgreSQL failover: hypotheses (written before the runs)

Measured from the client's side with the drill writer (`experiments/e7/writer.py`): 50 numbered
INSERTs per second through `pg-main-rw` into the database `drill`, every attempt logged as `ok`
(acknowledged), `fail` (definitely not written) or `unk` (sent, no answer within 2 s). After each
run the rows that exist are compared with the acknowledgements (`writer_report.py`):

- **write outage (RTO of the write path)**: from the first attempt without acknowledgement to the
  next acknowledgement;
- **lost writes (RPO)**: acknowledged commits whose rows are missing afterwards.

Starting point: CloudNativePG 1.30.1, three instances (zone-a/b/c, `podAntiAffinityType: required`),
asynchronous streaming replication (`pg_stat_replication`: `async`, `wal_sender_timeout` and
`wal_receiver_timeout` 5 s), `failoverDelay` 0, primary pg-main-3 on ent-worker3. The writer runs on
a node that the run does not touch.

| | Run | Hypothesis | Reasoning |
|---|---|---|---|
| F0 | Rolling update (new `priorityClassName`, the Barman Cloud plugin's sidecar in every instance pod) with `primaryUpdateMethod: switchover` | Replicas first, no effect on writes; then one write outage of **2-10 s** during the switchover; **0 lost writes** | A switchover is planned: the old primary shuts down cleanly and the replica is promoted only after it has received all WAL up to the shutdown checkpoint |
| F1 | Primary pod force-deleted (`--grace-period=0 --force`) | The operator sees the deletion immediately (watch) and promotes the most advanced replica: write outage **5-15 s**; **0 lost writes** (at most a handful) | On one LAN the replicas are about a millisecond behind; an acknowledged commit is lost only if it was acknowledged in the last instant before the kill |
| F2 | The primary's node frozen (`docker pause`, 120 s) | Nothing happens until the node is marked NotReady (about 45-50 s, E6) and the primary's pod becomes not ready; then failover. Write outage **45-60 s**; **0 lost writes** (at most a handful). After the unpause the old primary is rewound (pg_rewind) and rejoins as a replica by itself | A frozen node still answers TCP from its kernel, so no client sees a reset; detection depends on the node lease |
| F3 | Replication from the primary cut for 60 s (iptables on the primary's node, only replica -> primary :5432), then the primary's node frozen | During the cut nothing fails: the primary keeps acknowledging (asynchronous). Failover promotes a replica that is about 60 s behind: **about 3000 acknowledged writes lost (RPO ~ 60 s)**, i.e. everything written during the cut. No guard stops the promotion | CloudNativePG promotes the most advanced replica, however far behind; with `archive_timeout` 5 min and ~0.5 MB of WAL no segment reaches the archive during the cut, so restore_command cannot fill the gap |
| F4 | F3 again with synchronous replication (`synchronous: {method: any, number: 1, dataDurability: required}`) | Normal commits slower (p50 roughly 1.5-3 times F2's). During the cut **no write is acknowledged** (every attempt `unk` after 2 s); after the failover **0 lost writes**; the `unk` writes committed locally on the old primary are gone after the rewind (never acknowledged). Write outage about 60 s + 45-60 s | A commit waits until one standby has flushed it: durability bought with availability - with both standbys unreachable the primary stops accepting writes |

Not measured here: the outage that the storefront's users see (asyncpg pool with
`command_timeout` 10 s) - observed separately with k6 if the writer results leave time.

## Added after F0, before F0b

F0 did not test a switchover: the rollout that introduced the WAL-archiver sidecar restarted the
primary in place (`f0-rollout/analysis.md`). F0b tests the switchover part of the F0 hypothesis
directly: `kubectl cnpg promote pg-main pg-main-2` (planned switchover to the replica on
ent-worker2, which then holds the primary for F1-F4: it hosts neither the CloudNativePG operator,
ent-worker3, nor the Barman Cloud plugin, ent-worker).

| | Run | Hypothesis |
|---|---|---|
| F0b | Planned switchover (`kubectl cnpg promote`) | One write outage of **2-10 s**; **0 lost writes** |

## Added after F1, before F2

F0b: 10.7 s, 0 lost. F1: 26.9 s, 0 lost - 16 s of it the new primary waiting for the primary lease
(Lease data/pg-main, 15 s) that the killed primary had not released (`f1-delete/analysis.md`).

The primary goes back to pg-main-2 (ent-worker2) by a planned switchover first (F0c, a second
switchover sample). F2 adds a second writer that connects straight to the old primary's pod address
instead of pg-main-rw - a client with a stale address or a long-lived connection - to see whether
the old primary accepts writes after the unpause.

| | Run | Hypothesis |
|---|---|---|
| F0c | Planned switchover to pg-main-2 | as F0b: about 10 s, 0 lost |
| F2 | (unchanged, above) plus the lease: the frozen primary cannot renew its lease, which has expired long before the node is marked NotReady | write outage 45-60 s through pg-main-rw, 0 lost |
| F2-Z | The direct writer after the unpause | the old primary acknowledges writes for at most about 2 s after the unpause, until its instance manager finds the lease taken and stops PostgreSQL; **those writes are lost** (rewound away) |
