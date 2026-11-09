# E6 zone partition: hypotheses (written before the run)

Run: `experiments/e6/partition.sh partition-1 ent-worker 300 30` - zone-a (ent-worker) cut off from
zone-b and zone-c for 300 s under 30 it/s; the control plane and the load balancer stay reachable.

node-2 showed that a frozen node costs about one minute: until its endpoints are removed (52 s)
nearly every request failed, because a few timeouts on the frozen pods opened the gateway's
breakers, which are per service, not per endpoint (node-2-analysis.log). After node-2 every
catalog, gateway and payments replica runs in zone-c (the scheduler does not rebalance); in zone-a:
one of the two waypoints, the Argo CD controller, Grafana, Tempo, a PostgreSQL replica, a NATS server.

| | Hypothesis |
|---|---|
| Q1 | ent-worker stays Ready and its endpoints stay ready the whole time: Kubernetes does not see a partition |
| Q2 | Failures last as long as the partition, not one minute: the zone-a waypoint keeps receiving connections it cannot serve, and connections that the load balancer sends to ent-worker's NodePort cannot reach the gateways in zone-c; the breakers keep opening |
| Q3 | Prometheus (zone-b) reports the targets in zone-a as down within about a minute: the partition is visible to monitoring, not to the scheduler |
| Q4 | Within a minute after the partition ends, failures stop |
