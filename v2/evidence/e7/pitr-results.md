# E7 point-in-time recovery: results against the hypotheses

Hypotheses: `pitr-prediction.md` (P1-P6 committed in 10407e5/98c955f before pitr-1; P1', P4' in
0e2be74 before pitr-2). Drill: `experiments/e7/pitr.sh`; k6 at 5 iterations/s throughout.

| | Hypothesis | pitr-1 (job deletes every order) | pitr-2 (job deletes the last 5 minutes) | |
|---|---|---|---|---|
| P1 / P1' | first restore, 60 s after the accident, fails: the WAL around the target is not archived yet | **succeeded** (healthy after 90 s): the 211 350 row deletions wrote WAL that filled and archived segments AC-AF within 40 s | **failed** after 64 s (job: 141 rows, 12 kB of WAL; segment BF with the target still current); supplement: "FATAL: recovery ended before configured recovery target was reached" (`pitr-2/archive-lag.log`) | P1 refuted, P1' confirmed |
| P2 | after a forced WAL switch the second restore reaches the target in 2-4 min | - (not needed) | switch 15:16:25, archived 15:16:26.7, healthy after **95 s** | faster than predicted |
| P3 | pg-pitr holds every order id from before the accident and none after | 0 missing, newest 15:07:19.039 < target 15:07:19.215 | 0 missing, newest 15:14:18.989 < target 15:14:19.649 | confirmed |
| P4 / P4' | copy-back inserts exactly the deleted rows; nothing missing, later orders untouched | 211 350 inserted = 211 350 deleted; 0 missing; 212 later orders kept (`ids-summary.txt`) | 141 inserted = 141 deleted; 0 missing; 289 later orders kept | confirmed |
| P5 | a few restored orders are stale | 1: PENDING, although its `orders.confirmed` event (outbox) is from 125 ms after the target - reconciled from the outbox (`pitr-1/reconcile.log`) | 0 | confirmed |
| P6 | 5-10 min from noticing to the rows being back | **103 s** | **173 s** (with the failed first attempt) | refuted (faster) |

The storefront kept serving during both drills: k6 0.15 % and 0.08 % failed requests, order p95
269 ms and 261 ms. Each restore replayed WAL across the timelines of the failover drills (the base
backup is from timeline 2, the primary was on timeline 10).

Lessons:

- The archive is behind the primary by up to `archive_timeout` (5 min) - unless the accident itself
  writes a lot of WAL. A restore right after a small accident needs a forced segment switch
  (`SELECT pg_switch_wal()`) on the primary first; a mass deletion pushes its own WAL out within
  seconds.
- Restoring next to production and copying the rows back keeps everything written after the
  accident; restoring production itself to the target would have discarded 212 and 289 newer orders.
- A copied-back row is the version of the target time. Changes made after it (here one
  confirmation) must be replayed from another record - the outbox, kept in the same transaction as
  every order change (chapter 2), is one.
