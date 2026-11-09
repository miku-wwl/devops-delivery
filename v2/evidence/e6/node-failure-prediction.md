# E6 node failure: hypotheses (written before the run)

Run: `experiments/e6/node-failure.sh node-1 ent-worker 420 30` - ent-worker (zone-a) frozen with
`docker pause` for 420 s under 30 it/s. Chosen because ent-worker3 holds the PostgreSQL primary,
the only Valkey and OpenBao (their failover belongs to E7) and ent-worker2 holds Prometheus.

On ent-worker before the run: catalog (1 of 2), inventory (1 of 2), orders (1 of 2), the notifier
(its only replica), **the waypoint (its only replica)**, KEDA, the Kyverno background controller,
NATS (1 of 3), a PostgreSQL replica. Every other storefront service has its second replica on
ent-worker3 (both gateways and both payments are on ent-worker3: ScheduleAnyway, chapter 5).

The naive expectation "every service has two replicas, one node may fail" does not hold for the
waypoint: every call between storefront services goes through it (chapter 3).

| | Hypothesis | Checked by |
|---|---|---|
| N1 | The node turns NotReady (condition Unknown) 40-60 s after the pause (node monitor grace period) | watch.txt |
| N2 | From the pause until a waypoint runs again, practically every request that needs another service fails - browse included - not only the requests that would have reached pods on ent-worker | k6 failures per 10 s |
| N3 | The pods on ent-worker are evicted about 300 s after the node became unreachable (default toleration `node.kubernetes.io/unreachable`, 300 s); only then does the ReplicaSet create replacements, and a new waypoint starts on another node: recovery at roughly 6 min | events, watch.txt |
| N4 | Some replacements may not fit: ent-worker2 has 98 % of its memory requested | Pending count in watch.txt, FailedScheduling events |
| N5 | Notifications wait in JetStream while the only notifier is gone and are sent after it returns; none is lost | notifier sent vs orders confirmed |
| N6 | After the unpause the node comes back Ready; nothing moves back to it (the scheduler does not rebalance) | final placement |
