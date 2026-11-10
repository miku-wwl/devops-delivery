# E9 exemplars and tail sampling: results

Hypotheses: `exemplars-prediction.md` (committed before the check). Records: `exemplars.log` (first
run, image b13e3cf, 10 % head sampling), `exemplars-2.log` (second run, image 05a04fe, 100 % head
sampling), `tracing-cost.log`, `screens/grafana-slo-exemplars.png`, `screens/grafana-exemplar-trace.png`.

| | Hypothesis | Measured | |
|---|---|---|---|
| X1 | exemplars only in buckets above 1 s after the latency injection; none before | before: none; after: le=2.0 18, le=5.0 4 - **and 30 in le=0.005**: the gateway's breaker answered 503 within about 1 ms, and an error is exemplified whatever its duration (by design). Second run: le=2.0 21, le=5.0 3, le=0.005 33 | **refuted** (the prediction forgot the fast errors) |
| X2 | every exemplar's trace ID resolves in Tempo | first run: **1 of 5** (a 3011 ms request); the other four do not exist. Production head-samples 10 % of the traces (`tracesSampleRatio: "0.1"`, E3): a request that was not sampled still has a trace ID, and its exemplar pointed at a trace that was never recorded. Fixed: exemplars only for sampled spans (`trace_flags.sampled`), head sampling 100 %. Second run: **5 of 5** | refuted, fixed, confirmed |

The figure: the exemplar of a 1.06 s observation (trace c950ab6e...) opens a 1.23 s checkout whose
critical path is orders' call `GET /products/sku-010`, 1.01 s - the injected catalog latency.

Tail sampling during the incident (08:23:30-08:35:00, observation, not pre-registered): 4770 traces
decided; the error policy kept 86, the 10 % policy 486, the latency policy none. Tempo held 84 error
traces for 670 failed checkouts: head sampling had already dropped 9 of 10 requests before the
collector saw them - tail sampling cannot keep what it never receives. Also: the gateway retried a
failed order with the same idempotency key and answered 200 (an idempotent replay), so some failed
attempts sit inside traces whose root span is fine.

The cost of tracing every request (same k6 load, 5-minute rates, `tracing-cost.log`):

| | 10 % head sampling | 100 %, tail sampling decides |
|---|---|---|
| gateway requests/s | 17.7 | 17.0 |
| CPU of the six services | 0.393 cores | 0.413 cores (+5 %; +9 % per request) |
| spans arriving at the collector | 28.9/s | 291/s |
| spans stored in Tempo | 3.4/s | 29.9/s (8.7x) |
| collector CPU / memory | 0.009 cores / 92 MiB | 0.013 cores / 118 MiB |

Before, the two samplers multiplied: about 1 % of the spans reached Tempo, and only a tenth of the
errors. Now the tail sampler alone decides: every error and every slow trace, 10 % of the rest.
