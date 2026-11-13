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

## Second run (node-2), after the fixes - written before the run

node-1 confirmed N1 (NotReady after 46 s), N2 (100 % of requests failed from t=10 s to t=320 s,
browse included), N3 (evictions at t=331 s, recovery at about t=345 s), N4 (Grafana could not be
placed: insufficient memory), N5 (JetStream: everything delivered and acknowledged, no
redelivery) and N6. Not predicted: the replacement metrics-server preempted Prometheus on
ent-worker2, where its volume pins it (incident-2).

Fixes since: two waypoints, one in zone-a (ent-worker) and one in zone-b, with a disruption budget;
two notifiers (zone-b, zone-c); PriorityClass platform-critical for Prometheus; metrics-server
requests 64Mi. Memory requested: 95 % (ent-worker), 97 %, 99 %. On ent-worker now: one catalog
(of 2), one waypoint (of 2), the Argo CD application controller, Grafana, Tempo, a PostgreSQL
replica, a NATS server, metrics-server.

| | Hypothesis |
|---|---|
| M1 | Failures only until ent-worker turns NotReady (about 46 s) - the requests that the frozen waypoint or catalog would have answered; resilient retries recover part of them. No failures after that |
| M2 | After the evictions (t ~ 330 s) most replacements cannot be placed (memory requested 97-99 % on the other nodes): the second waypoint, Grafana, the Argo CD controller stay Pending until ent-worker is back - the storefront keeps running on its remaining replicas |
| M3 | Prometheus stays where it is (priority platform-critical) and records the whole run |
| M4 | The Argo CD controller is gone while the node is frozen: GitOps does not sync in that time (no change is made, so nothing is lost) |
