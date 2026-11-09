# E7 PostgreSQL failover: results against the hypotheses

Hypotheses: `failover-prediction.md` (each section committed before its runs: 0156bef, b18340e,
46d7256, 10407e5, 04ce00f). Measured with the drill writer (50 INSERTs/s through pg-main-rw, 2 s
deadline per attempt); details and timelines in each run's directory (`run.txt`, `report.txt`,
`watch.txt`, `operator.log`, `events.txt`, `analysis.md`).

| Run | Fault | Write outage | Lost acknowledged writes | Hypothesis |
|---|---|---|---|---|
| F0 | rolling update that introduced the WAL-archiver sidecar | 27.2 s, after 3 min without new connections | 0 | outage refuted: no switchover ("Primary is missing the WAL-archiver sidecar; recreating it in place"), smart shutdown 180 s |
| F0b | planned switchover (`kubectl cnpg promote`) | 10.7 s | 0 | outage slightly above 2-10 s, loss confirmed |
| F0c | planned switchover | 11.7 s | 0 | as F0b |
| F0d | planned switchover | 8.0 s | 0 | confirmed |
| F0e | planned switchover, synchronous replication | 14.4 s | 0 | slightly above |
| F1 | primary pod force-deleted | 26.9 s | 0 | outage refuted (5-15 s): 16 s waiting for the primary lease |
| F2 | primary's node frozen 120 s | 78.0 s | 0 through the service; **7** on a connection straight to the old primary | outage refuted (45-60 s): 50.7 s node lease + 16 s primary lease; split brain of 2.5 s after the unpause confirmed |
| F3 | replication cut 57 s, then the primary's node frozen; asynchronous | 73.7 s after the freeze | **3017** (everything acknowledged during the cut) | confirmed (about 3000) |
| F4 | as F3, synchronous replication (ANY 1, required) | 137.9 s (59 s cut + 79 s freeze/failover) | **0** | loss confirmed; no acknowledgement during the cut confirmed; 2 of 30 unknown outcomes had committed (refuted: "unknown" is not "not written") |

Commit latency (p50 / p99 of acknowledged INSERTs): asynchronous 2.7-3.1 ms / 8-12 ms (F0-F3),
synchronous 5.1-5.9 ms / 15-16 ms (F0e, F4): about 2 times, within the predicted 1.5-3 times.

What the numbers decompose into:

- **Planned switchover, 8-14 s**: the old primary stops and releases the lease, the replica is
  promoted (redo, timeline history read from the archive), the operator relabels the rw service,
  clients reconnect.
- **Unclean loss of the primary, +16 s**: the new primary must wait for the primary lease (15 s)
  the old one never released (F1, F2) - split-brain protection, paid in every unplanned failover.
- **Frozen node, +50 s**: nobody notices before the node is NotReady; a frozen node's kernel keeps
  completing TCP handshakes, so connections to it hang instead of failing (F2-F4).
- **Split brain after the node returns, 2.5 s**: the old primary is writable until its own
  instance manager notices (F2): 7 acknowledged writes lost on a direct connection, and a replica
  that streamed from it was out of replication for 17 minutes (incident E7-1).
- **Asynchronous replication + replica lag + loss of the primary = lost commits**, as many as the
  lag (F3). Synchronous replication turned the same double fault into a write outage instead (F4).

F4: the alerts added after incident E7-1 went pending 35 s after the cut, but the single Prometheus
runs on the same node as the frozen primary; they fired only after the unpause, when the failover
was over (`f4-cut-freeze-sync/alerts.log`).

Kept on the platform: synchronous replication `ANY 1`, `dataDurability: required` (an
acknowledged order survives the loss of any one instance; both standbys gone = writes wait);
`primaryUpdateMethod: switchover`; the alert rules.
