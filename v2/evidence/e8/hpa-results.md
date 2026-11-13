# E8 scale-out re-test: results against the hypotheses

Hypotheses: `hpa-prediction.md` (fcd6186 before hpa-l4/hpa-l7; 5d157da before run A). Same load
step in every run (`experiments/e4/hpa-timeline.sh`: 30 -> 170 -> 30 iterations/s, 120/300/420 s),
gateway HPA 2-6 pods at 100 % of a 500m request.

| | Hypothesis | Measured | |
|---|---|---|---|
| H1 | L4: the added pods get (almost) no requests | `hpa-l4`: pods added at +48 s and +93 s; in every minute of the high stage only the two original pods served (135-150 requests/s each), the added ones none | confirmed |
| H2 | L7: every added pod gets requests within ~10 s of being Ready, the load spreads evenly | `hpa-l7`: the first added pod served 79 requests/s in its first full minute; at the end all four shared the load (22-44/s each) | confirmed |
| H3 | L7: failures only in the first minute, < 5 % of the stage | `hpa-l7` 57.20 %, run A 49.18 % of the high stage failed | refuted |
| H4 | L7 costs 1-2 ms at the median (browse, low stage) | 11.6 ms (L7) against 12.4 ms (L4) | refuted (no measurable cost) |
| H5 | run A: the entrance retries a large share of the requests | **0 retries** (`envoy_cluster_upstream_rq_retry`); Istio's default route policy lists `retriable-status-codes` without any code, so a 503 is not retried | refuted |
| H6 | run B: retries off | not run - with no retries there was nothing to switch off | - |

What the failures were (run A, high stage, `hpa-l7-retries.log` and Prometheus): the entrance forwarded
66 409 requests to the gateway pods; they answered 40 704 x 503, 19 540 x 200, 3067 x 201, 745 x 504.
The gateway's own rejection counter: **circuit_open 40 010**, retry_budget 734, bulkhead_full 398 -
its per-service breaker towards an overloaded upstream refused most requests (the effect of chapter
7, here under load instead of a fault). More gateway pods do not add capacity behind the gateway.

Where the time went: the gateway itself answered fast (p50 4 ms, p95 387 ms, its own histogram); the
entrance measured p95 **9446 ms** for the same requests (`istio_request_duration_milliseconds`,
reporter source). The requests waited between the entrance's Envoy and the gateway application;
pending-request overflows at the entrance: 0. The cause was not determined (candidates: the gateway
pods' accept queue and the ambient HBONE path under overload; the entrance's connection and
pending gauges were not among the exported stats). k6 reached its cap of 600 virtual users 14-21 s
into the step and dropped iterations - which also makes the two entrances' totals not directly
comparable.

Conclusion: the layer-7 entrance does what chapter 5 asked of it - new pods share the load at once.
It does not make a step above the system's capacity succeed: the limit is behind the gateway, and the
gateway's breakers and an unexplained queue in front of it decide what the clients see.
