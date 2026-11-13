# F0 (rolling update) against the hypothesis

Hypothesis (failover-prediction.md, committed in 0156bef before the run): replicas first without
effect on writes, then one write outage of 2-10 s during a switchover, 0 lost writes.

| | Hypothesis | Measured (run.txt, report.txt, watch.txt, operator.log, events.txt) | |
|---|---|---|---|
| Replicas first | no effect on writes | pg-main-1 14:08:06-14:08:46, pg-main-2 14:08:48-14:09:10 recreated; no failed write before 14:12:15 | confirmed |
| Switchover | 2-10 s outage | **no switchover**: operator log 14:09:21 "Primary is missing the WAL-archiver sidecar; recreating it in place instead of switching over"; phase "Primary instance is being restarted without a switchover" | refuted |
| Outage | 2-10 s | **27.2 s** without any acknowledgement (14:12:15.4-14:12:42.6, 13 `fail` + 1 `unk`), preceded by **3 min without new connections** (rw service without a ready endpoint 14:09:21-14:12:41) | refuted |
| Lost writes | 0 | 0 (16 024 acknowledged, all present; the 1 unknown outcome was not committed) | confirmed |

What happened to the primary pod (events.txt): 14:09:21 "Stopping container postgres", 14:12:14
readiness probe 500, 14:12:21 rescheduled on the same node, 14:12:22-33 first pull of
plugin-barman-cloud-sidecar:v0.15.1 (11.0 s, 109 MB), 14:12:34 PostgreSQL started, 14:12:41 healthy.

Why 3 minutes: deleting an instance pod starts a *smart* shutdown, which lets existing sessions run
on and refuses new ones, for `smartShutdownTimeout` (default 180 s); then a fast shutdown. 14:09:21
+ 180 s = 14:12:21. The drill writer, holding one connection, kept committing on the old primary for
those 3 minutes (its writes were streamed to the replicas as usual). The storefront pools did the
same: open connections orders 4, inventory 2, catalog 2 at 14:10:00 and 14:11:30; 0 at 14:12:30;
2/2/2 at 14:13:00; no acquire timeouts (no load was running). A client that opens a connection per
request would have seen about 3 min 20 s of outage, the writer saw 27 s: the measured RTO depends
on how the client connects.

Why no switchover: the change introduced the WAL-archiver sidecar; the operator does not promote a
replica while the primary lacks the archiver and restarts the primary in place instead. This is a
one-time effect of switching archiving on; the planned switchover is measured separately (F0b).
