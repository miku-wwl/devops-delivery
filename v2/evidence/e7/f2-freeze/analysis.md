# F2 (primary's node frozen 120 s) against the hypotheses

| | Hypothesis | Measured | |
|---|---|---|---|
| F2 | write outage 45-60 s through pg-main-rw, 0 lost | **78.0 s** (14:31:10.1-14:32:28.1), 0 lost (6235 acknowledged, all present) | outage refuted, loss confirmed |
| F2 rejoin | old primary rewound, rejoins by itself | pg_rewind at 14:33:13 ("servers diverged at WAL location 0/A22C21B0 on timeline 5"), replica at 14:33:31, healthy 14:33:33, no manual step | confirmed |
| F2-Z | a client connected straight to the old primary gets writes acknowledged for at most about 2 s after the unpause; they are lost | **7 acknowledged writes lost** (seq 1168-1174, acknowledged 14:33:06.48-14:33:06.58); the old primary was writable for **2.5 s** after the unpause (14:33:04.0-14:33:06.5) | confirmed (window 2.5 s) |

## The 78 s

| Time | s after the freeze | What (watch.txt, operator.log, `kubectl logs pg-main-1/pg-main-2 -c postgres`) |
|---|---|---|
| 14:31:10.1 | 0 | `docker pause ent-worker2` |
| 14:32:00.8 | 50.7 | node NotReady, pod not ready; operator "Current primary isn't healthy, initiating a failover", target pg-main-1 |
| 14:32:01.1 | 51.0 | pg-main-1 "Acquiring primary lease" |
| 14:32:17.2 | 67.1 | "Acquired primary lease" - 16 s, although the frozen primary's last renewal was 51 s old |
| 14:32:21.9 | 71.8 | promotion done (redo 1.9 s, timeline 6 after reading history files from the archive) |
| 14:32:26.6 | 76.5 | operator "Setting primary label" (pg-main-rw -> pg-main-1) |
| 14:32:28.1 | 78.0 | first acknowledgement |

Detection is the node lease (50 s), not CloudNativePG: the operator's status requests to the
frozen instance did not fail fast - the frozen node's kernel completed the TCP handshakes, the
TLS handshakes then hung (14:33:04, right after the unpause, the old instance logged a burst of
"TLS handshake error from 10.240.3.127", the operator's address). The lease wait is the same 16 s
as in F1, independent of how long the old primary had been gone (3.7 s in F1, 51 s here): the new
primary waits a full lease duration (15 s) from when it starts trying - apparently counted from its
own first observation of the lease, not from the renew time stored in it, the leader-election rule
that makes clock differences between nodes harmless (an inference from the two measurements).

## Split brain for 2.5 s

After the unpause the old primary was a writable primary on the old timeline until its instance
manager reconciled: 14:33:06.466 "This is the former primary instance. Shutting it down to allow it
to be demoted to a replica", fast shutdown. In those 2.5 s:

- two statements frozen in flight completed on the old timeline (PostgreSQL log 14:33:04.617:
  "duration: 113989.145 ms statement: INSERT ... 'f2-freeze-z', 1110" and seq 1326 of the writer
  using the service) - both had been given up by their clients after 2 s (`unk`), both are gone;
- the direct writer connected at 14:33:06.47 and got 7 commits acknowledged before the shutdown,
  all 7 discarded by pg_rewind.

pg-main-rw stopped pointing at the old primary at 14:32:00 (pod not ready) - clients that resolve
the service were safe; the risk is any connection that outlives a failover: a pooled connection, a
cached address, a client connecting to a pod address. The instance manager fences the old primary
only after the node is back and it has looked at the cluster status; PostgreSQL itself does not
know about the lease.
