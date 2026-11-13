# E9 exemplars: hypotheses (written before the check)

Since b13e3cf (rolled out with !41) every service records the trace ID as an exemplar on its request
duration histogram - but only for a request that failed (5xx) or took 1 s or more, exactly the traces
the collector's tail sampling always keeps (errors; slower than 1 s; 10 % of the rest). The check:
catalog answers with 1.2 s of injected latency (`/admin/faults`, 45 s) under the running k6 load.

| | Hypothesis | Measured by |
|---|---|---|
| X1 | the gateway's duration histogram carries exemplars after the injection, only in buckets above 1 s; before it (fast, successful requests only) none | Prometheus `query_exemplars` |
| X2 | every exemplar's trace ID resolves in Tempo (kept by the "slow" policy), including the catalog span with the injected latency | Tempo API `/api/traces/<id>` |

Not pre-registered (measured after the drill, reported as observations): how many traces tail sampling
kept during the incident, by policy.
