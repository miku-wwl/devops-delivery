# E7 point-in-time recovery: hypotheses (written before the run)

Run: `experiments/e7/pitr.sh pitr-1 5 60`. k6 keeps the storefront busy (5 iterations/s, browse
and orders). Right before the accident the primary closes its current WAL segment (known starting
point). The accident: a cleanup job, meant for FAILED orders older than 30 days, runs as
`DELETE FROM orders WHERE created_at < now()` and deletes every order. 60 s later it is noticed;
a recovery cluster pg-pitr (one instance) is restored from the archive to the job's start time
(server clock), the deleted rows are copied back into production with
`INSERT ... ON CONFLICT DO NOTHING`. Ground truth for the checks: the order ids taken before the
accident. Archive: base backup 14:15-14:16 UTC, WAL archived continuously, `archive_timeout` 5 min.

| | Hypothesis | Reasoning |
|---|---|---|
| P1 | The first restore, 60 s after the accident, **fails**: "recovery ended before configured recovery target was reached" | The WAL from the segment switch up to and beyond the target is still in the primary's current segment, not in the archive; recovery must see a commit after the target to stop there, and PostgreSQL (13+) refuses to open a database short of its target |
| P2 | After a forced WAL switch (`pg_switch_wal()`) the segment is archived within seconds and the second restore reaches the target in **2-4 min** | Taking the base backup took 50 s, restoring it should take about as long; then about an hour of mostly small WAL segments |
| P3 | pg-pitr contains every order id that existed before the accident, and no order created after it | Replay stops at the first commit after the target time - the DELETE itself |
| P4 | The copy-back inserts exactly as many rows as the job deleted; afterwards no id from before the accident is missing and the orders placed after the accident are untouched | The ids are UUIDs; new orders cannot collide with restored ones |
| P5 | A few restored orders are stale: still PENDING although the services tried to confirm them after the target (their UPDATE found no row) - at most the orders in flight at the target (a handful at ~2 orders/s) | A logical copy-back returns rows as of the target time; later changes to them were never made |
| P6 | From noticing the accident to the rows being back: **5-10 min**, about half of it lost to the failed first attempt | P1 + P2 |
